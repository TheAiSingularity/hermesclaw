import chalk from "chalk";
import { resolve, dirname } from "node:path";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { parse as parseYaml } from "yaml";
import { runPreflight, printPreflightResults } from "../lib/preflight.js";
import { registryList, registryGet } from "../lib/registry.js";
import { isSandboxRunning } from "../lib/sandbox.js";
import { exec } from "../lib/exec.js";
import { redactString } from "../lib/credential-filter.js";
import { getProvider } from "../lib/providers.js";
import { getCredential, resolveApiKey } from "../lib/credentials.js";
import { validateProvider } from "../lib/validate.js";
import { getHermesclawHome } from "../lib/constants.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "../../..");

interface DoctorOptions {
  quick?: boolean;
}

function countFiles(dir: string, opts?: { pattern?: RegExp; type?: "file" | "dir"; maxDepth?: number }): number {
  if (!existsSync(dir)) return 0;
  try {
    const entries = readdirSync(dir, { withFileTypes: true });
    let count = 0;
    const pattern = opts?.pattern;
    const type = opts?.type;
    for (const entry of entries) {
      if (type === "dir" && entry.isDirectory()) {
        if (!pattern || pattern.test(entry.name)) count++;
      } else if ((!type || type === "file") && entry.isFile()) {
        if (!pattern || pattern.test(entry.name)) count++;
      }
    }
    return count;
  } catch {
    return 0;
  }
}

function countFilesRecursive(dir: string): number {
  if (!existsSync(dir)) return 0;
  try {
    let count = 0;
    const walk = (d: string) => {
      for (const entry of readdirSync(d, { withFileTypes: true })) {
        const full = resolve(d, entry.name);
        if (entry.isFile()) count++;
        else if (entry.isDirectory()) walk(full);
      }
    };
    walk(dir);
    return count;
  } catch {
    return 0;
  }
}

async function validateYamlFiles(dir: string): Promise<{ ok: string[]; errors: string[] }> {
  const ok: string[] = [];
  const errors: string[] = [];
  if (!existsSync(dir)) return { ok, errors };

  const walk = (d: string) => {
    for (const entry of readdirSync(d, { withFileTypes: true })) {
      const full = resolve(d, entry.name);
      if (entry.isFile() && entry.name.endsWith(".yaml")) {
        try {
          const content = readFileSync(full, "utf-8");
          parseYaml(content);
          ok.push(full.replace(REPO_ROOT + "/", ""));
        } catch (e: any) {
          errors.push(`${full.replace(REPO_ROOT + "/", "")}: ${e.message}`);
        }
      } else if (entry.isDirectory()) {
        walk(full);
      }
    }
  };
  walk(dir);
  return { ok, errors };
}

export async function doctorCommand(opts: DoctorOptions = {}): Promise<void> {
  const quick = opts.quick ?? false;

  console.log("");
  console.log(chalk.bold("HermesClaw Doctor"));
  console.log("═".repeat(50));

  // ── Preflight ────────────────────────────────────────────────────────────
  const preflight = await runPreflight();
  printPreflightResults(preflight);

  // ── Sandboxes ────────────────────────────────────────────────────────────
  const names = await registryList();
  if (names.length === 0) {
    console.log(chalk.dim("  No sandboxes registered."));
  } else {
    console.log(chalk.bold("Sandboxes"));
    console.log("─".repeat(50));
    for (const name of names) {
      const running = await isSandboxRunning(name);
      const entry = await registryGet(name);
      const status = running ? chalk.green("running") : chalk.yellow("stopped");
      console.log(`  ${chalk.cyan(name)} — ${status} (${entry?.tier ?? "unknown"} tier)`);
    }
  }

  // ── Inference Route ──────────────────────────────────────────────────────
  console.log("");
  console.log(chalk.bold("Inference"));
  console.log("─".repeat(50));
  const { stdout, exitCode } = await exec("openshell", ["inference", "get"]);
  if (exitCode === 0) {
    console.log(`  ${chalk.green("✓")} ${redactString(stdout) || "Inference route configured"}`);
  } else {
    console.log(`  ${chalk.yellow("⚠")} No inference route configured`);
  }

  // ── Provider-aware inference health ──────────────────────────────────────
  if (names.length > 0) {
    console.log("");
    console.log(chalk.bold("Inference Health"));
    console.log("─".repeat(50));

    for (const name of names) {
      const entry = await registryGet(name);
      if (!entry?.provider) {
        console.log(`  ${chalk.dim(name)} — ${chalk.dim("no provider configured")}`);
        continue;
      }
      const provider = getProvider(entry.provider);
      if (!provider) {
        console.log(`  ${chalk.dim(name)} — ${chalk.dim(`unknown provider: ${entry.provider}`)}`);
        continue;
      }

      const apiKey =
        resolveApiKey(provider.envKey) ??
        (await getCredential(provider.envKey)) ??
        "";
      const baseUrl =
        (await getCredential(`${provider.id}_base_url`)) ??
        provider.defaultBaseUrl ??
        "";

      const model = entry.model ?? "";
      const origLog = console.log;
      console.log = () => {};
      const result = await validateProvider(provider.endpointType, baseUrl, apiKey, model);
      console.log = origLog;
      const displayUrl = baseUrl.replace(/https?:\/\//, "").replace(/\/v1\/?$/, "");

      if (result.valid) {
        console.log(`  ${chalk.green("✓")} ${chalk.cyan(name)} — ${entry.provider} / ${model} (${displayUrl})`);
      } else {
        console.log(`  ${chalk.red("✗")} ${chalk.cyan(name)} — ${entry.provider} / ${model} (${displayUrl})`);
        console.log(`    ${chalk.dim(result.error ?? "unreachable")}`);
      }
    }
  }

  // ── Sandbox Image ───────────────────────────────────────────────────────
  console.log("");
  console.log(chalk.bold("Sandbox Image"));
  console.log("─".repeat(50));

  // Check the version inside each running sandbox (the actual deployed
  // image), rather than inspecting the local `hermesclaw:latest` tag which
  // may be stale — `hermesclaw onboard` builds one-off tagged images
  // (openshell/sandbox-from:*) and uploads them to the gateway.
  let checkedAnyImage = false;
  for (const name of names) {
    const running = await isSandboxRunning(name);
    if (!running) continue;
    checkedAnyImage = true;
    const verCheck = await exec("openshell", [
      "sandbox", "download", name, "/etc/hermes-version", "/tmp/.hermesclaw-doctor/",
    ]);
    if (verCheck.exitCode === 0) {
      try {
        const ver = readFileSync("/tmp/.hermesclaw-doctor/hermes-version", "utf-8").trim();
        if (ver) {
          console.log(`  ${chalk.green("✓")} ${chalk.cyan(name)} — Hermes ${ver}`);
        } else {
          console.log(`  ${chalk.yellow("⚠")} ${chalk.cyan(name)} — /etc/hermes-version is empty`);
        }
      } catch {
        console.log(`  ${chalk.yellow("⚠")} ${chalk.cyan(name)} — could not read downloaded version file`);
      }
    } else {
      console.log(`  ${chalk.yellow("⚠")} ${chalk.cyan(name)} — no /etc/hermes-version (pre-v0.3.3 build)`);
    }
  }

  if (!checkedAnyImage) {
    // Fall back to local Docker image if no sandboxes are running
    const imgInspect = await exec("docker", [
      "image", "inspect", "hermesclaw:latest",
      "--format", "{{.Created}}",
    ]);
    if (imgInspect.exitCode === 0) {
      const created = imgInspect.stdout.trim().slice(0, 10);
      console.log(`  ${chalk.green("✓")} hermesclaw:latest (built ${created})`);
      const verCheck = await exec("docker", [
        "run", "--rm", "hermesclaw:latest", "cat", "/etc/hermes-version",
      ]);
      if (verCheck.exitCode === 0 && verCheck.stdout.trim()) {
        console.log(`  ${chalk.green("✓")} Pinned Hermes version: ${verCheck.stdout.trim()}`);
      } else {
        console.log(`  ${chalk.yellow("⚠")} No /etc/hermes-version (pre-v0.3.3 build)`);
      }
    } else {
      console.log(`  ${chalk.dim("—")} No sandboxes running and hermesclaw:latest not built`);
    }
  }

  // ── Config File ──────────────────────────────────────────────────────────
  console.log("");
  console.log(chalk.bold("Configuration"));
  console.log("─".repeat(50));

  const hermesclawHome = getHermesclawHome();
  const hermesHome = resolve(process.env.HOME ?? "/root", ".hermes");
  const configPaths = [
    resolve(hermesclawHome, "config.yaml"),
    resolve(hermesHome, "config.yaml"),
  ];
  const configFound = configPaths.find((p) => existsSync(p));
  if (configFound) {
    console.log(`  ${chalk.green("✓")} ${configFound}`);
  } else {
    console.log(`  ${chalk.yellow("⚠")} No config.yaml found`);
  }

  // ── Model Files ──────────────────────────────────────────────────────────
  const modelsDir = resolve(hermesclawHome, "models");
  const modelCount = countFiles(modelsDir, { pattern: /\.gguf$/i });
  if (modelCount > 0) {
    console.log(`  ${chalk.green("✓")} ${modelCount} .gguf model(s) in ${modelsDir}`);
  } else {
    console.log(`  ${chalk.dim("—")} No .gguf files in ${modelsDir}`);
  }

  // ── Memory / Skill Counts ───────────────────────────────────────────────
  const memoriesDir = resolve(hermesHome, "memories");
  const memoryCount = countFilesRecursive(memoriesDir);
  console.log(`  ${chalk.green("✓")} ${memoryCount} memory file(s) in ${memoriesDir}`);

  const skillsDir = resolve(hermesHome, "skills");
  const skillCount = countFiles(skillsDir, { type: "dir" });
  console.log(`  ${chalk.green("✓")} ${skillCount} skill(s) in ${skillsDir}`);

  // ── Policy YAML Validation ──────────────────────────────────────────────
  console.log("");
  console.log(chalk.bold("Policy YAML"));
  console.log("─".repeat(50));

  const openshellDir = resolve(REPO_ROOT, "openshell");
  const yamlResult = await validateYamlFiles(openshellDir);

  if (yamlResult.errors.length === 0 && yamlResult.ok.length > 0) {
    console.log(`  ${chalk.green("✓")} ${yamlResult.ok.length} YAML file(s) valid`);
  } else if (yamlResult.ok.length === 0 && yamlResult.errors.length === 0) {
    console.log(`  ${chalk.dim("—")} No policy YAML found in openshell/`);
  } else {
    if (yamlResult.ok.length > 0) {
      console.log(`  ${chalk.green("✓")} ${yamlResult.ok.length} valid`);
    }
    for (const err of yamlResult.errors) {
      console.log(`  ${chalk.red("✗")} ${err}`);
    }
  }

  // ── Inference Smoke Test (skip with --quick) ────────────────────────────
  if (!quick && names.length > 0) {
    console.log("");
    console.log(chalk.bold("Inference Smoke Test"));
    console.log("─".repeat(50));

    for (const name of names) {
      const entry = await registryGet(name);
      if (!entry?.provider) {
        console.log(`  ${chalk.dim(name)} — skipped (no provider)`);
        continue;
      }
      const provider = getProvider(entry.provider);
      if (!provider) {
        console.log(`  ${chalk.dim(name)} — skipped (unknown provider)`);
        continue;
      }

      const apiKey =
        resolveApiKey(provider.envKey) ??
        (await getCredential(provider.envKey)) ??
        "";
      const baseUrl =
        (await getCredential(`${provider.id}_base_url`)) ??
        provider.defaultBaseUrl ??
        "";
      const model = entry.model ?? "";

      try {
        const cleanUrl = baseUrl.replace(/\/$/, "");
        const url = provider.endpointType === "anthropic"
          ? `${cleanUrl}/v1/messages`
          : provider.endpointType === "ollama"
            ? `${cleanUrl}/v1/chat/completions`
            : `${cleanUrl}/chat/completions`;

        const headers: Record<string, string> = { "Content-Type": "application/json" };
        if (provider.endpointType === "anthropic") {
          headers["x-api-key"] = apiKey;
          headers["anthropic-version"] = "2023-06-01";
        } else if (apiKey) {
          headers["Authorization"] = `Bearer ${apiKey}`;
        }

        const body = provider.endpointType === "anthropic"
          ? JSON.stringify({ model, max_tokens: 16, messages: [{ role: "user", content: "Reply with exactly: ok" }] })
          : JSON.stringify({ model, max_tokens: 16, messages: [{ role: "user", content: "Reply with exactly: ok" }] });

        const res = await fetch(url, {
          method: "POST",
          headers,
          body,
          signal: AbortSignal.timeout(30_000),
        });

        if (res.ok) {
          console.log(`  ${chalk.green("✓")} ${chalk.cyan(name)} — inference round-trip succeeded`);
        } else {
          const text = await res.text().catch(() => "");
          console.log(`  ${chalk.yellow("⚠")} ${chalk.cyan(name)} — HTTP ${res.status}: ${text.slice(0, 120)}`);
        }
      } catch (err: any) {
        console.log(`  ${chalk.yellow("⚠")} ${chalk.cyan(name)} — ${err.message}`);
      }
    }
  } else if (quick) {
    console.log("");
    console.log(chalk.dim("  Inference smoke test skipped (--quick)"));
  }

  console.log("");
}
