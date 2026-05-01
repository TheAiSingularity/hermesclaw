import { spawn, type SpawnOptions, type ChildProcess } from "node:child_process";
import chalk from "chalk";

export type CreatePhase = "build" | "upload" | "create" | "ready";

export interface StreamCommandResult {
  status: number;
  output: string;
  sawProgress: boolean;
}

export interface StreamCommandOptions {
  initialPhase?: CreatePhase;
  heartbeatIntervalMs?: number;
  silentPhaseMs?: number;
  logLine?: (line: string) => void;
  env?: NodeJS.ProcessEnv;
  cwd?: string;
  /** Poll this function to detect sandbox readiness before the stream exits. */
  readyCheck?: (() => boolean) | null;
  /** Interval (ms) between readyCheck polls. Default 2000. */
  pollIntervalMs?: number;
}

// Patterns that indicate we're in the "build" phase (for phase detection only).
const BUILD_PHASE_PATTERNS: readonly RegExp[] = [
  /^ {2}Building image /,
  /^ {2}Step \d+\/\d+ : /,
  /^#\d+ \[/,
  /^#\d+ (DONE|CACHED)\b/,
];

const UPLOAD_PROGRESS_PATTERNS: readonly RegExp[] = [
  /^ {2}Pushing image /,
  /^\s*\[progress\]/,
  /^ {2}Image .*available in the gateway/,
];

// Lines shown to the user. Excludes noisy internal/metadata Docker lines
// like "#1 [internal] load build definition" — only shows actual build steps
// (e.g. "#4 [1/14] FROM ..."), CACHED layers, and milestone markers.
const VISIBLE_PROGRESS_PATTERNS: readonly RegExp[] = [
  /^ {2}Building image /,
  /^ {2}Step \d+\/\d+ : /,
  /^#\d+ \[\d+\/\d+\] /,        // actual numbered build steps: #N [stage/total]
  /^#\d+ CACHED\b/,              // cache hits
  /^ {2}Context: /,
  /^ {2}Gateway: /,
  /^Successfully built /,
  /^Successfully tagged /,
  /^ {2}Built image /,
  ...UPLOAD_PROGRESS_PATTERNS,
  /^Created sandbox: /,
  /^✓ /,
];

const PHASE_LABELS: Record<CreatePhase, string> = {
  build: "Building sandbox image...",
  upload: "Uploading image into OpenShell gateway...",
  create: "Creating sandbox in gateway...",
  ready: "Waiting for sandbox to become ready...",
};

const HEARTBEAT_LABELS: Record<CreatePhase, string> = {
  build: "Still building sandbox image...",
  upload: "Still uploading image into OpenShell gateway...",
  create: "Still creating sandbox in gateway...",
  ready: "Still waiting for sandbox to become ready...",
};

function matchesAny(line: string, patterns: readonly RegExp[]): boolean {
  return patterns.some((p) => p.test(line));
}

function getDisplayWidth(): number {
  return Math.max(60, Number(process.stdout.columns || 100));
}

function trimLine(line: string): string {
  const maxLen = Math.max(40, getDisplayWidth() - 4);
  if (line.length <= maxLen) return line;
  return `${line.slice(0, maxLen - 3)}...`;
}

/**
 * Spawn a command and stream its output with phase-based progress display.
 * Inspired by NemoClaw's streamSandboxCreate — shows phase transitions,
 * filters noisy output, and prints heartbeats during silent periods.
 */
export function streamWithProgress(
  command: string,
  args: string[],
  options: StreamCommandOptions = {},
): Promise<StreamCommandResult> {
  const logLine = options.logLine ?? ((line: string) => console.log(line));
  const heartbeatIntervalMs = options.heartbeatIntervalMs ?? 5000;
  const silentPhaseMs = options.silentPhaseMs ?? 15000;

  const spawnOpts: SpawnOptions = {
    stdio: ["ignore", "pipe", "pipe"],
    env: options.env ?? process.env,
    cwd: options.cwd,
  };

  const child: ChildProcess = spawn(command, args, spawnOpts);

  const lines: string[] = [];
  let pending = "";
  let lastPrintedLine = "";
  let sawProgress = false;
  let settled = false;

  let currentPhase: CreatePhase | null = null;
  let lastHeartbeatPhase: CreatePhase | null = null;
  let lastHeartbeatBucket = -1;

  const startedAt = Date.now();
  let lastOutputAt = startedAt;

  const pollIntervalMs = options.pollIntervalMs ?? 2000;
  let resolvePromise: (result: StreamCommandResult) => void;

  function elapsedSeconds(): number {
    return Math.max(0, Math.floor((Date.now() - startedAt) / 1000));
  }

  function printProgressLine(line: string): void {
    const display = trimLine(line);
    if (display !== lastPrintedLine) {
      logLine(display);
      lastPrintedLine = display;
    }
  }

  function setPhase(nextPhase: CreatePhase | null): void {
    if (!nextPhase || nextPhase === currentPhase) return;
    currentPhase = nextPhase;
    lastHeartbeatPhase = null;
    lastHeartbeatBucket = -1;
    const label = nextPhase ? PHASE_LABELS[nextPhase] : null;
    if (label) printProgressLine(`  ${label}`);
  }

  function flushLine(rawLine: string): void {
    const line = rawLine.replace(/\r/g, "").trimEnd();
    if (!line) return;
    lines.push(line);
    lastOutputAt = Date.now();

    if (matchesAny(line, BUILD_PHASE_PATTERNS)) {
      setPhase("build");
    } else if (matchesAny(line, UPLOAD_PROGRESS_PATTERNS)) {
      setPhase("upload");
    } else if (/^Created sandbox: /.test(line)) {
      setPhase("create");
    }

    if (matchesAny(line, VISIBLE_PROGRESS_PATTERNS) && line !== lastPrintedLine) {
      printProgressLine(line);
      sawProgress = true;
    }
  }

  function onChunk(chunk: Buffer | string): void {
    pending += chunk.toString();
    const parts = pending.split("\n");
    pending = parts.pop() ?? "";
    parts.forEach(flushLine);
  }

  function finish(status: number): void {
    if (settled) return;
    settled = true;
    if (pending) flushLine(pending);
    if (readyTimer) clearInterval(readyTimer);
    clearInterval(heartbeatTimer);
    resolvePromise({ status, output: lines.join("\n"), sawProgress });
  }

  child.stdout?.on("data", onChunk);
  child.stderr?.on("data", onChunk);

  const readyTimer = options.readyCheck
    ? setInterval(() => {
        if (settled) return;
        try {
          if (!options.readyCheck?.()) return;
        } catch { return; }
        setPhase("ready");
        printProgressLine("  Sandbox reported Ready before create stream exited; continuing.");
        try { child.kill("SIGTERM"); } catch { /* best effort */ }
        sawProgress = true;
        finish(0);
      }, pollIntervalMs)
    : null;
  readyTimer?.unref?.();

  setPhase(options.initialPhase ?? "build");

  const heartbeatTimer = setInterval(() => {
    if (settled) return;
    const silentForMs = Date.now() - lastOutputAt;
    if (silentForMs < silentPhaseMs) return;

    const elapsed = elapsedSeconds();
    const bucket = Math.floor(elapsed / 15);
    if (currentPhase === lastHeartbeatPhase && bucket === lastHeartbeatBucket) {
      return;
    }

    const label = currentPhase
      ? HEARTBEAT_LABELS[currentPhase]
      : "Still working...";

    const heartbeatLine = `  ${label} (${elapsed}s elapsed)`;
    if (trimLine(heartbeatLine) !== lastPrintedLine) {
      printProgressLine(heartbeatLine);
      lastHeartbeatPhase = currentPhase;
      lastHeartbeatBucket = bucket;
    }
  }, heartbeatIntervalMs);
  heartbeatTimer.unref?.();

  return new Promise((resolve) => {
    resolvePromise = resolve;

    child.on("error", (error) => {
      lines.push(`spawn failed: ${error.message}`);
      finish(1);
    });

    child.on("close", (code) => {
      // Final ready-check: sandbox may have become Ready between last poll and exit
      if (code && code !== 0 && options.readyCheck) {
        try {
          if (options.readyCheck()) { finish(0); return; }
        } catch { /* fall through */ }
      }
      finish(code ?? 1);
    });
  });
}

/**
 * Stream an OpenShell sandbox create command with full phase tracking
 * (build → upload → create → ready).
 */
export async function streamSandboxCreate(
  args: string[],
  options: StreamCommandOptions = {},
): Promise<StreamCommandResult> {
  return streamWithProgress("openshell", args, {
    initialPhase: "build",
    ...options,
  });
}
