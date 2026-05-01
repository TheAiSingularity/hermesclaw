import chalk from "chalk";
import { spawnSync } from "node:child_process";
import { isSandboxRunning } from "../lib/sandbox.js";
import { registryGet } from "../lib/registry.js";
import {
  mkdirSync, existsSync, readdirSync, writeFileSync, readFileSync, unlinkSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { HERMESCLAW_HOME } from "../lib/constants.js";

const BACKUP_DIR = join(HERMESCLAW_HOME, "rebuild-backups");
const SANDBOX_TMP_ZIP = "/tmp/hermesclaw-snapshot.zip";

// ── SSH helpers ─────────────────────────────────────────────────

function getSshConfig(name: string): string | null {
  const result = spawnSync("openshell", ["sandbox", "ssh-config", name], {
    encoding: "utf-8",
    stdio: ["ignore", "pipe", "pipe"],
    timeout: 15_000,
  });
  return result.status === 0 ? result.stdout : null;
}

function writeTempSshConfig(sshConfig: string): string {
  const tmp = join(tmpdir(), `hermesclaw-snap-${process.pid}-${Date.now()}.conf`);
  writeFileSync(tmp, sshConfig, { mode: 0o600 });
  return tmp;
}

function sshArgs(configFile: string, name: string): string[] {
  return [
    "-F", configFile,
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "ConnectTimeout=10",
    "-o", "LogLevel=ERROR",
    `openshell-${name}`,
  ];
}

function cleanupFile(path: string): void {
  try { unlinkSync(path); } catch { /* best effort */ }
}

function sshExec(
  configFile: string, name: string, cmd: string,
  opts?: { input?: Buffer; timeout?: number },
): { status: number | null; stdout: Buffer; stderr: string } {
  const result = spawnSync("ssh", [...sshArgs(configFile, name), cmd], {
    input: opts?.input,
    stdio: [opts?.input ? "pipe" : "ignore", "pipe", "pipe"],
    timeout: opts?.timeout ?? 300_000,
    maxBuffer: 512 * 1024 * 1024,
  });
  return {
    status: result.status,
    stdout: result.stdout ?? Buffer.alloc(0),
    stderr: result.stderr?.toString().substring(0, 1000) || "",
  };
}

// ── Create ──────────────────────────────────────────────────────

async function snapshotCreate(name: string): Promise<void> {
  const entry = await registryGet(name);
  if (!entry) {
    throw new Error(`Sandbox '${name}' not found in registry.`);
  }

  const running = await isSandboxRunning(name);
  if (!running) {
    throw new Error(`Sandbox '${name}' is not running. Start it first.`);
  }

  console.log(chalk.dim(`  Creating snapshot of ${name}...`));

  const sshConfig = getSshConfig(name);
  if (!sshConfig) {
    throw new Error(`Could not get SSH config for '${name}'. Is the sandbox reachable?`);
  }

  const configFile = writeTempSshConfig(sshConfig);
  try {
    // Use hermes backup to create a proper backup inside the sandbox
    const backup = sshExec(configFile, name,
      `hermes backup -o ${SANDBOX_TMP_ZIP}`,
      { timeout: 300_000 },
    );

    if (backup.status !== 0) {
      throw new Error(`hermes backup failed (exit ${backup.status}): ${backup.stderr}`);
    }

    // Download the zip over SSH
    const download = sshExec(configFile, name,
      `cat ${SANDBOX_TMP_ZIP}`,
      { timeout: 300_000 },
    );

    if (download.status !== 0 || download.stdout.length === 0) {
      throw new Error(`Failed to download snapshot: ${download.stderr}`);
    }

    // Clean up temp file inside sandbox
    sshExec(configFile, name, `rm -f ${SANDBOX_TMP_ZIP}`, { timeout: 10_000 });

    // Write to host
    const snapDir = join(BACKUP_DIR, name);
    mkdirSync(snapDir, { recursive: true });
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const snapFile = join(snapDir, `hermesclaw-snap-${timestamp}.zip`);
    writeFileSync(snapFile, download.stdout, { mode: 0o600 });

    console.log(chalk.green(`  ✓ Snapshot created: ${snapFile}`));
  } finally {
    cleanupFile(configFile);
  }
}

// ── List ────────────────────────────────────────────────────────

function snapshotFiles(name: string): string[] {
  const snapDir = join(BACKUP_DIR, name);
  if (!existsSync(snapDir)) return [];
  return readdirSync(snapDir)
    .filter((f) => f.startsWith("hermesclaw-snap-") && (f.endsWith(".zip") || f.endsWith(".tar.gz")))
    .sort();
}

async function snapshotList(name: string): Promise<void> {
  const snaps = snapshotFiles(name);

  if (snaps.length === 0) {
    console.log(chalk.dim(`No snapshots for '${name}'.`));
    return;
  }

  console.log("");
  console.log(chalk.bold(`Snapshots for: ${name}`));
  console.log("─".repeat(50));
  for (const snap of snaps) {
    const ts = snap.replace("hermesclaw-snap-", "").replace(/\.(zip|tar\.gz)$/, "");
    console.log(`  ${ts}`);
  }
  console.log("");
}

// ── Restore ─────────────────────────────────────────────────────

async function snapshotRestore(name: string, prefix?: string): Promise<void> {
  const snaps = snapshotFiles(name);

  if (snaps.length === 0) {
    throw new Error(`No snapshots found for '${name}'.`);
  }

  let target: string;
  if (prefix) {
    const matches = snaps.filter((s) => s.includes(prefix));
    if (matches.length === 0) {
      throw new Error(`No snapshot matching '${prefix}'.`);
    }
    if (matches.length > 1) {
      throw new Error(`Ambiguous prefix '${prefix}' matches ${matches.length} snapshots.`);
    }
    target = matches[0];
  } else {
    target = snaps[snaps.length - 1];
  }

  const snapPath = join(BACKUP_DIR, name, target);
  const isZip = target.endsWith(".zip");
  console.log(chalk.dim(`  Restoring from: ${target}`));

  const sshConfig = getSshConfig(name);
  if (!sshConfig) {
    throw new Error(`Could not get SSH config for '${name}'. Is the sandbox reachable?`);
  }

  const configFile = writeTempSshConfig(sshConfig);
  try {
    const snapData = readFileSync(snapPath);

    if (isZip) {
      // Upload zip over SSH and restore with hermes import
      const upload = sshExec(configFile, name,
        `cat > ${SANDBOX_TMP_ZIP}`,
        { input: snapData, timeout: 300_000 },
      );
      if (upload.status !== 0) {
        throw new Error(`Failed to upload snapshot: ${upload.stderr}`);
      }

      const restore = sshExec(configFile, name,
        `hermes import ${SANDBOX_TMP_ZIP} --force`,
        { timeout: 300_000 },
      );
      if (restore.status !== 0) {
        throw new Error(`hermes import failed (exit ${restore.status}): ${restore.stderr}`);
      }

      sshExec(configFile, name, `rm -f ${SANDBOX_TMP_ZIP}`, { timeout: 10_000 });
    } else {
      // Legacy .tar.gz: extract directly into /opt/data
      const extract = sshExec(configFile, name,
        "tar -xzf - -C /opt/data",
        { input: snapData, timeout: 300_000 },
      );
      if (extract.status !== 0) {
        throw new Error(`Restore failed (exit ${extract.status}): ${extract.stderr}`);
      }
    }

    sshExec(configFile, name,
      "chown -R sandbox:sandbox /opt/data",
      { timeout: 30_000 },
    );

    console.log(chalk.green(`  ✓ Restored snapshot for '${name}'.`));
  } finally {
    cleanupFile(configFile);
  }
}

export const snapshotCommand = {
  create: snapshotCreate,
  list: snapshotList,
  restore: snapshotRestore,
};
