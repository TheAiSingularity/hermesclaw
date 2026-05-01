import chalk from "chalk";
import { exec, hasCommand } from "./exec.js";
import { MIN_OPENSHELL_VERSION, MAX_OPENSHELL_VERSION, DEFAULT_GATEWAY_PORT } from "./constants.js";
import { createServer } from "node:net";
import { readFileSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";
import { platform, release } from "node:os";

export interface PreflightResult {
  docker: boolean;
  openshell: boolean;
  openshellVersion: string | null;
  podman: boolean;
  errors: string[];
  warnings: string[];
  // Enhanced host assessment fields
  isWsl: boolean;
  hasGpu: boolean;
  containerRuntime: string;
  dockerStorageDriver: string | null;
  hasNestedOverlayConflict: boolean;
  memoryMB: number | null;
  swapMB: number | null;
  dnsOk: boolean | null;
  gatewayPortAvailable: boolean | null;
}

function compareVersions(a: string, b: string): number {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const na = pa[i] ?? 0;
    const nb = pb[i] ?? 0;
    if (na !== nb) return na - nb;
  }
  return 0;
}

function detectWsl(): boolean {
  if (platform() !== "linux") return false;
  if (process.env.WSL_DISTRO_NAME || process.env.WSL_INTEROP) return true;
  try {
    const rel = release();
    if (/microsoft/i.test(rel)) return true;
    const proc = readFileSync("/proc/version", "utf-8");
    if (/microsoft/i.test(proc)) return true;
  } catch { /* ignore */ }
  return false;
}

function detectGpu(): boolean {
  try {
    const out = execSync("nvidia-smi -L 2>/dev/null", { encoding: "utf-8", timeout: 5000 });
    return out.trim().length > 0;
  } catch {
    return false;
  }
}

function getMemoryInfo(): { ramMB: number; swapMB: number } | null {
  if (platform() !== "linux") return null;
  try {
    const content = readFileSync("/proc/meminfo", "utf-8");
    const parse = (key: string) => {
      const m = content.match(new RegExp(`^${key}:\\s+(\\d+)`, "m"));
      return m ? Math.floor(parseInt(m[1], 10) / 1024) : 0;
    };
    return { ramMB: parse("MemTotal"), swapMB: parse("SwapTotal") };
  } catch {
    return null;
  }
}

function parseDockerStorageDriver(info: string): string | null {
  const jsonMatch = info.match(/"Driver"\s*:\s*"([^"]+)"/);
  if (jsonMatch) return jsonMatch[1];
  const textMatch = info.match(/^\s*Storage Driver:\s*(\S+)\s*$/m);
  return textMatch?.[1] ?? null;
}

function usesContainerdSnapshotter(info: string): boolean {
  return /io\.containerd\.snapshotter\.v1/.test(info);
}

function inferRuntime(info: string): string {
  const n = info.toLowerCase();
  if (n.includes("podman")) return "podman";
  if (n.includes("colima")) return "colima";
  if (n.includes("docker desktop")) return "docker-desktop";
  if (n.includes("docker") || n.trim()) return "docker";
  return "unknown";
}

async function checkPortAvailable(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const srv = createServer();
    srv.once("error", (err: NodeJS.ErrnoException) => {
      resolve(err.code !== "EADDRINUSE");
    });
    srv.listen(port, "127.0.0.1", () => {
      srv.close(() => resolve(true));
    });
  });
}

async function isGatewayRunning(expectedPort: number): Promise<boolean> {
  try {
    const { exitCode, stdout } = await exec("openshell", ["gateway", "info"]);
    if (exitCode !== 0) return false;
    const portMatch = stdout.match(/:(\d+)\s*$/m);
    return portMatch ? Number(portMatch[1]) === expectedPort : false;
  } catch {
    return false;
  }
}

function probeContainerDns(): boolean | null {
  try {
    const out = execSync(
      "docker run --rm --pull=missing busybox:latest nslookup registry.npmjs.org 2>&1",
      { encoding: "utf-8", timeout: 20_000 }
    );
    if (/\bName:\s*registry\.npmjs\.org\b/.test(out) && /\bAddress:\s*\d/.test(out)) {
      return true;
    }
    if (/no servers could be reached|connection timed out/i.test(out)) {
      return false;
    }
    return false;
  } catch {
    return null;
  }
}

export async function runPreflight(): Promise<PreflightResult> {
  const result: PreflightResult = {
    docker: false,
    openshell: false,
    openshellVersion: null,
    podman: false,
    errors: [],
    warnings: [],
    isWsl: false,
    hasGpu: false,
    containerRuntime: "unknown",
    dockerStorageDriver: null,
    hasNestedOverlayConflict: false,
    memoryMB: null,
    swapMB: null,
    dnsOk: null,
    gatewayPortAvailable: null,
  };

  // Host assessment
  result.isWsl = detectWsl();
  result.hasGpu = detectGpu();

  if (result.isWsl) {
    result.warnings.push("Running under WSL. Some Docker features may behave differently.");
  }

  // Check Docker
  let dockerInfo = "";
  if (await hasCommand("docker")) {
    const { exitCode, stdout } = await exec("docker", ["info", "--format", "{{json .}}"]);
    if (exitCode === 0) {
      result.docker = true;
      dockerInfo = stdout;
      result.containerRuntime = inferRuntime(dockerInfo);
      result.dockerStorageDriver = parseDockerStorageDriver(dockerInfo);

      // Nested overlay conflict: Docker 26+ on Linux with containerd snapshotter
      if (
        platform() === "linux" &&
        !result.isWsl &&
        result.containerRuntime === "docker" &&
        result.dockerStorageDriver === "overlayfs" &&
        usesContainerdSnapshotter(dockerInfo)
      ) {
        result.hasNestedOverlayConflict = true;
        result.warnings.push(
          "Docker uses containerd snapshotter with overlayfs — this can break k3s-in-Docker sandbox creation. " +
          "Consider switching to the overlay2 storage driver or disabling the containerd image store."
        );
      }
    } else {
      result.errors.push(
        "Docker is installed but not reachable. Is the Docker daemon running?"
      );
    }
  } else {
    result.errors.push(
      "Docker not found. Install: https://docs.docker.com/get-docker/"
    );
  }

  // Check Podman
  if (await hasCommand("podman")) {
    result.podman = true;
    if (!result.docker) {
      result.warnings.push(
        "Podman detected but Docker is the tested runtime. Podman may work but is not officially supported."
      );
    }
  }

  // Check OpenShell
  if (await hasCommand("openshell")) {
    result.openshell = true;
    const { stdout } = await exec("openshell", ["--version"]);
    const versionMatch = stdout.match(/(\d+\.\d+\.\d+)/);
    if (versionMatch) {
      result.openshellVersion = versionMatch[1];
      const ver = versionMatch[1];
      if (compareVersions(ver, MIN_OPENSHELL_VERSION) < 0) {
        result.errors.push(
          `OpenShell ${ver} is too old. Minimum required: ${MIN_OPENSHELL_VERSION}. ` +
          `Update: curl -fsSL https://www.nvidia.com/openshell.sh | bash`
        );
      } else if (compareVersions(ver, MAX_OPENSHELL_VERSION) >= 0) {
        result.errors.push(
          `OpenShell ${ver} is newer than tested maximum (${MAX_OPENSHELL_VERSION}). ` +
          `This version of HermesClaw may not be compatible.`
        );
      }
    }
  } else {
    result.errors.push(
      "OpenShell not found. Install: curl -fsSL https://www.nvidia.com/openshell.sh | bash"
    );
  }

  // Memory / swap check (Linux only)
  const mem = getMemoryInfo();
  if (mem) {
    result.memoryMB = mem.ramMB;
    result.swapMB = mem.swapMB;
    const totalMB = mem.ramMB + mem.swapMB;
    if (totalMB < 8000) {
      result.warnings.push(
        `Low memory: ${mem.ramMB} MB RAM + ${mem.swapMB} MB swap = ${totalMB} MB total. ` +
        `Recommend at least 8 GB. Consider adding swap: ` +
        `sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 && sudo chmod 600 /swapfile && ` +
        `sudo mkswap /swapfile && sudo swapon /swapfile`
      );
    }
  }

  // Port availability check — skip if the OpenShell gateway already owns the port
  const gatewayAlreadyRunning = await isGatewayRunning(DEFAULT_GATEWAY_PORT);
  if (gatewayAlreadyRunning) {
    result.gatewayPortAvailable = true;
  } else {
    result.gatewayPortAvailable = await checkPortAvailable(DEFAULT_GATEWAY_PORT);
    if (result.gatewayPortAvailable === false) {
      result.warnings.push(
        `Port ${DEFAULT_GATEWAY_PORT} is in use. The OpenShell gateway may fail to start. ` +
        `Check: lsof -i :${DEFAULT_GATEWAY_PORT}`
      );
    }
  }

  // Container DNS probe (only if Docker is available)
  if (result.docker) {
    result.dnsOk = probeContainerDns();
    if (result.dnsOk === false) {
      result.errors.push(
        "Container DNS resolution failed. Containers cannot reach external registries. " +
        "This is common on corporate networks that block outbound DNS (UDP:53) from Docker. " +
        "Fix: configure Docker to use your host's DNS resolver, or add " +
        "{ \"dns\": [\"<your-corporate-dns-ip>\"] } to /etc/docker/daemon.json and restart Docker."
      );
    }
  }

  return result;
}

export function printPreflightResults(result: PreflightResult): void {
  console.log("");
  console.log(chalk.bold("Preflight Checks"));
  console.log("─".repeat(50));

  const check = (ok: boolean, label: string, detail?: string) => {
    const icon = ok ? chalk.green("✓") : chalk.red("✗");
    const line = `  ${icon} ${label}`;
    console.log(detail ? `${line} ${chalk.dim(detail)}` : line);
  };

  check(result.docker, "Docker", result.docker
    ? `reachable (${result.containerRuntime})`
    : "not available"
  );
  check(
    result.openshell,
    "OpenShell",
    result.openshellVersion ? `v${result.openshellVersion}` : "not found"
  );

  if (result.hasGpu) {
    console.log(`  ${chalk.green("✓")} NVIDIA GPU detected`);
  }

  if (result.memoryMB != null) {
    const totalMB = result.memoryMB + (result.swapMB ?? 0);
    const ok = totalMB >= 8000;
    check(ok, "Memory", `${result.memoryMB} MB RAM + ${result.swapMB ?? 0} MB swap`);
  }

  if (result.gatewayPortAvailable != null) {
    check(
      result.gatewayPortAvailable,
      "Gateway port",
      result.gatewayPortAvailable && result.openshell
        ? `${DEFAULT_GATEWAY_PORT}/tcp (gateway running)`
        : `${DEFAULT_GATEWAY_PORT}/tcp`,
    );
  }

  if (result.dnsOk != null) {
    check(result.dnsOk, "Container DNS", result.dnsOk ? "resolves" : "blocked");
  }

  if (result.podman && !result.docker) {
    console.log(`  ${chalk.yellow("⚠")} Podman detected (untested runtime)`);
  }

  if (result.isWsl) {
    console.log(`  ${chalk.yellow("⚠")} Running under WSL`);
  }

  if (result.warnings.length > 0) {
    console.log("");
    for (const w of result.warnings) {
      console.log(chalk.yellow(`  ⚠ ${w}`));
    }
  }

  if (result.errors.length > 0) {
    console.log("");
    for (const e of result.errors) {
      console.log(chalk.red(`  ✗ ${e}`));
    }
  }

  console.log("");
}

export function preflightPassed(result: PreflightResult): boolean {
  return result.errors.length === 0;
}
