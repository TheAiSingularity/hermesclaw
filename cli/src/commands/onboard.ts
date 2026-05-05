import chalk from "chalk";
import { join, resolve, dirname } from "node:path";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { runPreflight, printPreflightResults, preflightPassed } from "../lib/preflight.js";
import { PROVIDERS, getProvider, getProviderChoices } from "../lib/providers.js";
import { validateProvider, listOllamaModels, getRecoveryMessage } from "../lib/validate.js";
import { getCredential, setCredential, resolveApiKey } from "../lib/credentials.js";
import {
  POLICY_TIERS,
  AVAILABLE_PRESETS,
  getTier,
  assemblePolicyFile,
} from "../lib/policy.js";
import {
  createSandbox,
  configureInference,
  destroySandbox,
  isSandboxRunning,
} from "../lib/sandbox.js";
import { registryGet } from "../lib/registry.js";
import {
  selectProvider,
  selectModel,
  promptApiKey,
  promptBaseUrl,
  selectTier,
  selectPresets,
  promptSandboxName,
  confirmAction,
  printSummary,
} from "../lib/ui.js";
import { HERMESCLAW_HOME } from "../lib/constants.js";
import { snapshotCommand } from "./snapshot.js";
import {
  createSession,
  loadSession,
  saveSession,
  clearSession,
  markStep,
  isStepComplete,
  completeSession,
  acquireOnboardLock,
  releaseOnboardLock,
  type OnboardSession,
} from "../lib/session.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_DOCKERFILE = resolve(__dirname, "../../../Dockerfile");

/**
 * Snapshot the sandbox's /opt/data before destroying it so the data can be
 * restored into the freshly-created replacement. Returns true if a snapshot
 * was successfully created (meaning a restore should be attempted later).
 */
async function snapshotBeforeDestroy(sandboxName: string): Promise<boolean> {
  const running = await isSandboxRunning(sandboxName);
  if (running) {
    console.log(chalk.dim(`  Backing up sandbox '${sandboxName}' before destroy...`));
    try {
      await snapshotCommand.create(sandboxName);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      console.log(chalk.yellow(`  ⚠ Snapshot failed: ${msg}`));
      console.log(chalk.yellow(`    Proceeding without backup.`));
      await destroySandbox(sandboxName);
      return false;
    }
  } else {
    console.log(chalk.yellow(`  Sandbox '${sandboxName}' is not running — skipping backup.`));
  }
  await destroySandbox(sandboxName);
  return running;
}

export interface OnboardOptions {
  nonInteractive?: boolean;
  resume?: boolean;
  fresh?: boolean;
  recreateSandbox?: boolean;
  from?: string;
  agent?: string;
  yesIAcceptThirdPartySoftware?: boolean;
}

export async function onboardCommand(opts: OnboardOptions): Promise<void> {
  console.log("");
  console.log(chalk.bold("HermesClaw Onboarding"));
  console.log("═".repeat(50));

  // ── Onboard lock ──────────────────────────────────────────────────────────
  if (!acquireOnboardLock()) {
    console.error(chalk.red("Another onboard process is already running."));
    process.exit(1);
  }

  try {
    await runOnboard(opts);
  } finally {
    releaseOnboardLock();
  }
}

async function runOnboard(opts: OnboardOptions): Promise<void> {
  // ── Third-party software notice ───────────────────────────────────────────
  const accepted =
    opts.yesIAcceptThirdPartySoftware ||
    process.env.HERMESCLAW_ACCEPT_THIRD_PARTY_SOFTWARE === "1";

  if (!accepted) {
    console.log("");
    console.log(chalk.yellow(
      "  HermesClaw uses third-party software including NVIDIA OpenShell,\n" +
      "  Docker, and inference provider SDKs. By continuing you acknowledge\n" +
      "  their respective licenses and terms of service."
    ));
    console.log("");
    if (opts.nonInteractive) {
      console.error(chalk.red("Pass --yes-i-accept-third-party-software or set HERMESCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1"));
      process.exit(1);
    }
    const ok = await confirmAction("Accept and continue?", true);
    if (!ok) {
      console.log("Aborted.");
      process.exit(0);
    }
  }

  // ── Session management ────────────────────────────────────────────────────
  if (opts.resume && opts.fresh) {
    console.error(chalk.red("--resume and --fresh are mutually exclusive."));
    process.exit(1);
  }

  let session: OnboardSession;

  if (opts.fresh) {
    clearSession();
    session = createSession();
    saveSession(session);
    console.log(chalk.dim("  Starting fresh onboard session."));
  } else if (opts.resume) {
    const existing = loadSession();
    if (existing && existing.resumable) {
      session = existing;
      console.log(chalk.dim(`  Resuming onboard session ${session.sessionId.slice(0, 8)}...`));
    } else {
      console.log(chalk.yellow("  No resumable session found. Starting fresh."));
      session = createSession();
      saveSession(session);
    }
  } else {
    const existing = loadSession();
    if (existing && existing.resumable) {
      if (opts.nonInteractive) {
        session = existing;
      } else {
        const resume = await confirmAction(
          "A previous onboard session was interrupted. Resume it?",
          true,
        );
        if (resume) {
          session = existing;
          console.log(chalk.dim(`  Resuming session ${session.sessionId.slice(0, 8)}...`));
        } else {
          clearSession();
          session = createSession();
          saveSession(session);
        }
      }
    } else {
      session = createSession();
      saveSession(session);
    }
  }

  if (opts.from) {
    session.dockerfilePath = resolve(opts.from);
  }

  // ── Step 1: Preflight ─────────────────────────────────────────────────────
  if (!isStepComplete(session, "preflight")) {
    markStep(session, "preflight", "in_progress");
    saveSession(session);

    const preflight = await runPreflight();
    printPreflightResults(preflight);

    if (!preflightPassed(preflight)) {
      markStep(session, "preflight", "failed");
      saveSession(session);
      console.error(chalk.red("Preflight checks failed. Fix the issues above and retry."));
      process.exit(1);
    }

    markStep(session, "preflight", "complete");
    saveSession(session);
  } else {
    console.log(chalk.dim("  ✓ Preflight (cached)"));
  }

  // ── Step 2: Provider Selection ────────────────────────────────────────────
  let providerId: string;
  let model: string = "";
  let apiKey = "";
  let baseUrl = "";

  if (isStepComplete(session, "provider_selection") && session.provider) {
    providerId = session.provider;
    model = session.model ?? "";
    console.log(chalk.dim(`  ✓ Provider: ${providerId}${model ? `, model: ${model}` : ""} (cached)`));
  } else {
    markStep(session, "provider_selection", "in_progress");
    saveSession(session);

    if (opts.nonInteractive) {
      providerId = process.env.HERMESCLAW_PROVIDER ?? "";
      model = process.env.HERMESCLAW_MODEL ?? "";
      if (!providerId) {
        console.error(chalk.red("HERMESCLAW_PROVIDER is required in non-interactive mode"));
        process.exit(1);
      }
    } else {
      providerId = await selectProvider(getProviderChoices());
    }

    session.provider = providerId;
    markStep(session, "provider_selection", "complete");
    saveSession(session);
  }

  const provider = getProvider(providerId);
  if (!provider) {
    console.error(chalk.red(`Unknown provider: ${providerId}`));
    process.exit(1);
  }

  // ── Step 3: Credential Collection ─────────────────────────────────────────
  if (!isStepComplete(session, "credentials")) {
    markStep(session, "credentials", "in_progress");
    saveSession(session);

    if (provider.requiresApiKey) {
      apiKey =
        resolveApiKey(provider.envKey) ??
        (await getCredential(provider.envKey)) ??
        "";

      if (!apiKey) {
        if (opts.nonInteractive) {
          console.error(chalk.red(`${provider.envKey} must be set in non-interactive mode`));
          process.exit(1);
        }
        apiKey = await promptApiKey(provider.envKey);
      }
      await setCredential(provider.envKey, apiKey);
    }

    if (provider.requiresBaseUrl) {
      baseUrl =
        process.env.HERMESCLAW_ENDPOINT_URL ??
        (await getCredential(`${provider.id}_base_url`)) ??
        "";

      if (!baseUrl) {
        if (opts.nonInteractive) {
          console.error(chalk.red("HERMESCLAW_ENDPOINT_URL is required for this provider"));
          process.exit(1);
        }
        baseUrl = await promptBaseUrl();
      }
      await setCredential(`${provider.id}_base_url`, baseUrl);
    } else {
      baseUrl = provider.defaultBaseUrl ?? "";
    }

    session.baseUrl = baseUrl;
    markStep(session, "credentials", "complete");
    saveSession(session);
  } else {
    apiKey = resolveApiKey(provider.envKey) ?? (await getCredential(provider.envKey)) ?? "";
    baseUrl = session.baseUrl ?? provider.defaultBaseUrl ?? "";
    console.log(chalk.dim("  ✓ Credentials (cached)"));
  }

  // ── Step 4: Model Selection ───────────────────────────────────────────────
  if (!model) {
    if (isStepComplete(session, "model_selection") && session.model) {
      model = session.model;
      console.log(chalk.dim(`  ✓ Model: ${model} (cached)`));
    } else {
      markStep(session, "model_selection", "in_progress");
      saveSession(session);

      if (provider.id === "ollama") {
        const ollamaModels = await listOllamaModels(baseUrl);
        if (opts.nonInteractive) {
          model = process.env.HERMESCLAW_MODEL ?? ollamaModels[0] ?? "llama3.1:8b";
        } else {
          model = await selectModel(ollamaModels.length > 0 ? ollamaModels : [], provider.name);
        }
      } else if (opts.nonInteractive) {
        model = process.env.HERMESCLAW_MODEL ?? provider.models[0] ?? "";
        if (!model) {
          console.error(chalk.red("HERMESCLAW_MODEL is required"));
          process.exit(1);
        }
      } else {
        model = await selectModel(provider.models, provider.name);
      }

      session.model = model;
      markStep(session, "model_selection", "complete");
      saveSession(session);
    }
  }

  // ── Step 5: Validate Endpoint ─────────────────────────────────────────────
  if (!isStepComplete(session, "validation")) {
    markStep(session, "validation", "in_progress");
    saveSession(session);

    const validation = await validateProvider(provider.endpointType, baseUrl, apiKey, model);

    if (!validation.valid) {
      console.warn(chalk.yellow(`  ⚠ Validation failed: ${validation.error}`));
      console.log(chalk.dim(`    ${getRecoveryMessage(validation)}`));

      if (opts.nonInteractive) {
        console.log(chalk.dim("  Continuing in non-interactive mode..."));
      } else if (validation.retryHint === "credential") {
        const reenter = await confirmAction("Re-enter API key?", true);
        if (reenter) {
          apiKey = await promptApiKey(provider.envKey);
          await setCredential(provider.envKey, apiKey);
          markStep(session, "credentials", "pending");
          markStep(session, "validation", "pending");
          saveSession(session);
          await runOnboard(opts);
          return;
        }
      } else if (validation.retryHint === "model") {
        const changeModel = await confirmAction("Choose a different model?", true);
        if (changeModel) {
          markStep(session, "model_selection", "pending");
          markStep(session, "validation", "pending");
          saveSession(session);
          await runOnboard(opts);
          return;
        }
      } else {
        const cont = await confirmAction("Continue anyway?", true);
        if (!cont) {
          markStep(session, "validation", "failed");
          saveSession(session);
          process.exit(1);
        }
      }
    }

    session.apiPath = validation.apiPath;
    console.log(chalk.green(`  ✓ Validated: ${model} via ${validation.apiPath}`));
    markStep(session, "validation", "complete");
    saveSession(session);
  } else {
    console.log(chalk.dim(`  ✓ Validation (cached)`));
  }

  const apiPath = session.apiPath ?? "openai-completions";

  // ── Step 6: Policy Tier Selection ─────────────────────────────────────────
  let tierName: string;
  let selectedPresets: string[];

  if (isStepComplete(session, "policy") && session.tier) {
    tierName = session.tier;
    selectedPresets = session.presets ?? [];
    console.log(chalk.dim(`  ✓ Policy: ${tierName} (cached)`));
  } else {
    markStep(session, "policy", "in_progress");
    saveSession(session);

    if (opts.nonInteractive) {
      tierName = process.env.HERMESCLAW_POLICY_TIER ?? "balanced";
      const tier = getTier(tierName);
      if (!tier) {
        console.error(
          chalk.red(`Invalid tier: ${tierName}. Valid: ${POLICY_TIERS.map((t) => t.name).join(", ")}`)
        );
        process.exit(1);
      }
      selectedPresets = tier.presets;
    } else {
      tierName = await selectTier(
        POLICY_TIERS.map((t) => ({
          value: t.name,
          name: t.name.charAt(0).toUpperCase() + t.name.slice(1),
          description: t.description,
        }))
      );
      const tier = getTier(tierName)!;
      selectedPresets = await selectPresets(
        AVAILABLE_PRESETS.map((p) => ({ value: p.id, name: p.name })),
        tier.presets
      );
    }

    session.tier = tierName;
    session.presets = selectedPresets;
    markStep(session, "policy", "complete");
    saveSession(session);
  }

  // ── Step 7: Sandbox Name ──────────────────────────────────────────────────
  let sandboxName: string;

  if (isStepComplete(session, "sandbox_name") && session.sandboxName) {
    sandboxName = session.sandboxName;
    console.log(chalk.dim(`  ✓ Sandbox name: ${sandboxName} (cached)`));
  } else {
    markStep(session, "sandbox_name", "in_progress");
    saveSession(session);

    if (opts.nonInteractive) {
      sandboxName = opts.agent ?? process.env.HERMESCLAW_SANDBOX_NAME ?? "hermesclaw-1";
    } else {
      sandboxName = await promptSandboxName(opts.agent ?? "hermesclaw-1");
    }

    session.sandboxName = sandboxName;
    markStep(session, "sandbox_name", "complete");
    saveSession(session);
  }

  // ── Step 8: Handle existing sandbox (selection drift detection) ────────────
  let hasSnapshot = false;
  const alreadyExists = await isSandboxRunning(sandboxName);
  if (alreadyExists) {
    const existing = await registryGet(sandboxName);
    const drift: string[] = [];
    if (existing) {
      if (existing.provider && existing.provider !== providerId) {
        drift.push(`provider: ${existing.provider} → ${providerId}`);
      }
      if (existing.model && existing.model !== model) {
        drift.push(`model: ${existing.model} → ${model}`);
      }
      if (existing.tier && existing.tier !== tierName) {
        drift.push(`tier: ${existing.tier} → ${tierName}`);
      }
    }

    const needsRebuild = drift.length > 0;

    if (opts.recreateSandbox || opts.nonInteractive) {
      hasSnapshot = await snapshotBeforeDestroy(sandboxName);
    } else if (needsRebuild) {
      console.log(chalk.yellow(`  Sandbox '${sandboxName}' exists but configuration changed:`));
      for (const d of drift) {
        console.log(chalk.yellow(`    • ${d}`));
      }

      const onlyInferenceChanged =
        drift.every((d) => d.startsWith("provider:") || d.startsWith("model:"));

      if (onlyInferenceChanged) {
        const reconfigure = await confirmAction(
          "Only inference changed. Reconfigure without rebuilding the sandbox?",
          true,
        );
        if (reconfigure) {
          const inferenceOk = await configureInference(provider, model, apiKey, baseUrl);
          if (inferenceOk) {
            console.log(chalk.green(`  ✓ Inference reconfigured for '${sandboxName}'.`));
            completeSession(session);
            printSummary(sandboxName, model, tierName);
            return;
          }
          console.log(chalk.yellow("  Inference reconfiguration failed. Proceeding to rebuild."));
        }
      }

      const recreate = await confirmAction("Delete and recreate sandbox?", true);
      if (recreate) {
        hasSnapshot = await snapshotBeforeDestroy(sandboxName);
      } else {
        console.log(chalk.green(`  Keeping existing sandbox '${sandboxName}'.`));
        completeSession(session);
        printSummary(sandboxName, model, tierName);
        return;
      }
    } else {
      const recreate = await confirmAction(
        `Sandbox '${sandboxName}' already exists (no config changes). Rebuild it?`,
        false,
      );
      if (recreate) {
        hasSnapshot = await snapshotBeforeDestroy(sandboxName);
      } else {
        console.log(chalk.green(`  Keeping existing sandbox '${sandboxName}'.`));
        completeSession(session);
        printSummary(sandboxName, model, tierName);
        return;
      }
    }
  }

  // ── Step 9: Assemble Policy and Create Sandbox ─────────────────────────────
  // Image build, upload, and sandbox creation happen in one streamed
  // `openshell sandbox create --from <Dockerfile>` command (same as NemoClaw).
  // Build args are patched into a staged copy of the Dockerfile before the call.
  if (!isStepComplete(session, "sandbox_create")) {
    markStep(session, "sandbox_create", "in_progress");
    saveSession(session);

    const dockerfilePath = session.dockerfilePath ?? DEFAULT_DOCKERFILE;
    if (!existsSync(dockerfilePath)) {
      console.error(chalk.red(`Dockerfile not found: ${dockerfilePath}`));
      process.exit(1);
    }

    const policyOutputPath = join(HERMESCLAW_HOME, "active-policy.yaml");
    await assemblePolicyFile(selectedPresets, policyOutputPath);

    const inferenceOk = await configureInference(provider, model, apiKey, baseUrl);
    if (!inferenceOk) {
      markStep(session, "sandbox_create", "failed");
      saveSession(session);
      console.error(chalk.red("Failed to configure inference routing. Run: hermesclaw onboard --resume"));
      process.exit(1);
    }

    const hostTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

    const created = await createSandbox({
      name: sandboxName,
      policyFile: policyOutputPath,
      dockerfilePath,
      provider: providerId,
      model,
      tier: tierName,
      presets: selectedPresets,
      buildArgs: {
        HERMESCLAW_MODEL: model,
        HERMESCLAW_INFERENCE_BASE_URL: baseUrl || "https://inference.local/v1",
        HERMESCLAW_INFERENCE_API: apiPath,
        HERMESCLAW_TZ: hostTimezone,
      },
    });

    if (!created) {
      markStep(session, "sandbox_create", "failed");
      saveSession(session);
      console.error(chalk.red("Sandbox creation failed. Run: hermesclaw onboard --resume"));
      process.exit(1);
    }

    markStep(session, "sandbox_create", "complete");
    saveSession(session);
  } else {
    console.log(chalk.dim("  ✓ Sandbox created (cached)"));
  }

  // ── Step 10: Restore snapshot into new sandbox ────────────────────────────
  if (hasSnapshot) {
    console.log(chalk.dim(`  Restoring backup into '${sandboxName}'...`));
    try {
      await snapshotCommand.restore(sandboxName);
    } catch {
      console.log(chalk.yellow(
        `  ⚠ Restore failed. Backup is still available at:\n` +
        `    ${join(HERMESCLAW_HOME, "rebuild-backups", sandboxName)}`
      ));
    }
  }

  // ── Complete ──────────────────────────────────────────────────────────────
  completeSession(session);
  printSummary(sandboxName, model, tierName);
}
