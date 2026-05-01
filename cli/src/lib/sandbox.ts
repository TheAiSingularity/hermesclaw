import { exec, spawnInteractive } from "./exec.js";
import { registryAdd, registryRemove } from "./registry.js";
import type { ProviderDefinition } from "./providers.js";
import { streamSandboxCreate } from "./progress.js";
import { writeFile, mkdir } from "node:fs/promises";
import { readFileSync, writeFileSync, mkdtempSync, cpSync, rmSync } from "node:fs";
import { existsSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { tmpdir, homedir } from "node:os";
import chalk from "chalk";

export interface CreateSandboxOptions {
  name: string;
  policyFile: string;
  dockerfilePath: string;
  gpu?: boolean;
  provider?: string;
  model?: string;
  tier?: string;
  presets?: string[];
  /** Build-time ARG overrides — patched into the Dockerfile before passing to openshell. */
  buildArgs?: Record<string, string>;
  /** Runtime env vars injected into the sandbox via `-- env KEY=VALUE`. */
  envArgs?: Record<string, string>;
}

/**
 * Stage a patched copy of the Dockerfile in a temp build context.
 * Rewrites ARG default values so `openshell sandbox create --from`
 * picks them up without needing `--build-arg` (which it doesn't support).
 */
function stageBuildContext(
  dockerfilePath: string,
  buildArgs: Record<string, string>,
): string {
  const srcDir = dirname(dockerfilePath);
  const buildCtx = mkdtempSync(join(tmpdir(), "hermesclaw-build-"));
  cpSync(srcDir, buildCtx, {
    recursive: true,
    filter: (src) => {
      const base = basename(src);
      return !["node_modules", ".git", ".venv", "__pycache__"].includes(base);
    },
  });
  const stagedDockerfile = join(buildCtx, "Dockerfile");
  if (basename(dockerfilePath) !== "Dockerfile") {
    cpSync(dockerfilePath, stagedDockerfile);
  }

  let content = readFileSync(stagedDockerfile, "utf-8");
  for (const [key, value] of Object.entries(buildArgs)) {
    if (!value) continue;
    content = content.replace(
      new RegExp(`^ARG ${key}=.*$`, "m"),
      `ARG ${key}=${value}`,
    );
  }

  // Bake MCP service URLs into the image so configure-mcp.sh can read them
  // at container startup. Only URLs — credentials flow through OpenShell
  // providers and the L7 proxy resolves placeholders at the network level.
  const mcpUrlsFile = join(homedir(), ".hermes", "mcp-urls.env");
  if (existsSync(mcpUrlsFile)) {
    const mcpLines = readFileSync(mcpUrlsFile, "utf-8")
      .split("\n")
      .filter((l) => l.includes("=") && !l.startsWith("#"))
      .map((l) => l.replace(/\\/g, "\\\\"))
      .join("\\n");
    if (mcpLines) {
      content = content.replace(
        /^WORKDIR\b/m,
        `RUN printf '${mcpLines}\\n' > /usr/local/share/hermes-defaults/mcp-urls.env\nWORKDIR`,
      );
    }
  }

  writeFileSync(stagedDockerfile, content);
  return buildCtx;
}

export async function createSandbox(opts: CreateSandboxOptions): Promise<boolean> {
  let buildCtx: string | null = null;
  let fromPath = opts.dockerfilePath;

  if (opts.buildArgs && Object.keys(opts.buildArgs).length > 0) {
    buildCtx = stageBuildContext(opts.dockerfilePath, opts.buildArgs);
    fromPath = join(buildCtx, "Dockerfile");
  }

  const cleanupBuildCtx = () => {
    if (buildCtx) {
      try { rmSync(buildCtx, { recursive: true, force: true }); } catch { /* best effort */ }
    }
  };
  process.on("exit", cleanupBuildCtx);

  try {
    const args = [
      "sandbox", "create",
      "--name", opts.name,
      "--from", fromPath,
      "--policy", opts.policyFile,
    ];
    if (opts.gpu) args.push("--gpu");

    const { stdout: providerList } = await exec("openshell", ["provider", "list"]);
    for (const line of providerList.split("\n").slice(1)) {
      const provName = line.trim().split(/\s+/)[0];
      if (provName) args.push("--provider", provName);
    }

    args.push("--");
    if (opts.envArgs && Object.keys(opts.envArgs).length > 0) {
      args.push("env");
      for (const [key, value] of Object.entries(opts.envArgs)) {
        if (value) args.push(`${key}=${value}`);
      }
    }
    args.push("/bin/true");

    const result = await streamSandboxCreate(args, { initialPhase: "build" });

    if (result.status !== 0) {
      console.log(chalk.red(`  ✗ Failed to create sandbox '${opts.name}'`));
      if (!result.sawProgress) {
        console.log("");
        for (const line of result.output.split("\n").slice(-20)) {
          console.log(chalk.dim(`    ${line}`));
        }
      }
      return false;
    }

    console.log(chalk.green(`  ✓ Sandbox '${opts.name}' created`));

    const profileDir = join(homedir(), ".hermes", "profiles", opts.name);
    const soulFile = join(profileDir, "SOUL.md");
    const isNewProfile = !existsSync(soulFile);
    if (isNewProfile) {
      await mkdir(profileDir, { recursive: true });
      await writeFile(
        soulFile,
        `# ${opts.name}\n\nYou are **${opts.name}**, an intelligent AI assistant powered by Hermes.\nYou run inside a sandboxed environment managed by HermesClaw.\n`
      );
    }

    // Upload the profile SOUL.md for new sandboxes so the agent uses
    // the customized persona rather than the base image default.
    // On rebuild the snapshot restore handles it.
    if (isNewProfile) {
      try {
        const uploadResult = await exec("openshell", [
          "sandbox", "upload", opts.name, soulFile, "/sandbox/.hermes/SOUL.md",
        ]);
        if (uploadResult.exitCode === 0) {
          console.log(chalk.green(`  ✓ SOUL.md uploaded from profile`));
        }
      } catch { /* best effort — default SOUL.md still works */ }
    }

    await registryAdd(opts.name, {
      policy: opts.tier ?? "restricted",
      profile: opts.name,
      provider: opts.provider,
      model: opts.model,
      tier: opts.tier,
      presets: opts.presets,
    });

    return true;
  } finally {
    cleanupBuildCtx();
    process.removeListener("exit", cleanupBuildCtx);
  }
}

export async function destroySandbox(name: string): Promise<boolean> {
  const { exitCode } = await exec("openshell", ["sandbox", "delete", name]);
  if (exitCode !== 0) return false;
  await registryRemove(name);
  return true;
}

export async function isSandboxRunning(name: string): Promise<boolean> {
  const { stdout } = await exec("openshell", ["sandbox", "list"]);
  return stdout.includes(name);
}

export async function connectToSandbox(name: string): Promise<void> {
  await spawnInteractive("openshell", ["sandbox", "connect", name]);
}

export async function getSandboxLogs(
  name: string,
  follow: boolean
): Promise<void> {
  const args = ["sandbox", "logs", name];
  if (follow) args.push("--follow");
  await spawnInteractive("openshell", args);
}

export async function ensureProvider(
  provider: ProviderDefinition,
  apiKey: string,
  baseUrl: string
): Promise<boolean> {
  const providerName = provider.openshellProvider;

  const { stdout: providerList } = await exec("openshell", ["provider", "list"]);
  if (providerList.includes(providerName)) {
    console.log(chalk.dim(`  Provider '${providerName}' already registered`));
    return true;
  }

  console.log(chalk.dim(`  Registering OpenShell provider '${providerName}'...`));

  const openshellBaseUrl =
    provider.openshellBaseUrl ?? baseUrl ?? provider.defaultBaseUrl ?? "";
  const credentialKey = apiKey || "empty";

  const createArgs = [
    "provider", "create",
    "--name", providerName,
    "--type", provider.openshellType,
    "--credential", `OPENAI_API_KEY=${credentialKey}`,
  ];

  if (openshellBaseUrl) {
    createArgs.push("--config", `OPENAI_BASE_URL=${openshellBaseUrl}`);
  }

  const { exitCode, stderr } = await exec("openshell", createArgs);
  if (exitCode !== 0) {
    console.error(chalk.red(`  Failed to create provider '${providerName}': ${stderr}`));
    return false;
  }

  console.log(chalk.green(`  ✓ Provider '${providerName}' created`));
  return true;
}

export async function configureInference(
  provider: ProviderDefinition,
  model: string,
  apiKey: string,
  baseUrl: string
): Promise<boolean> {
  const ok = await ensureProvider(provider, apiKey, baseUrl);
  if (!ok) return false;

  const { exitCode, stderr } = await exec("openshell", [
    "inference", "set",
    "--provider", provider.openshellProvider,
    "--model", model,
  ]);
  if (exitCode !== 0) {
    console.error(chalk.red(`  Failed to configure inference: ${stderr}`));
    return false;
  }

  console.log(chalk.green(`  ✓ Inference route: ${provider.openshellProvider} / ${model}`));
  return true;
}
