import { select, input, confirm, checkbox } from "@inquirer/prompts";
import chalk from "chalk";

const nvidiaGreen = chalk.hex("#76B900");

const theme = {
  prefix: {
    idle: chalk.blue("?"),
    done: chalk.green("✓"),
  },
};

export async function selectProvider(
  choices: { value: string; name: string }[]
): Promise<string> {
  return select({
    message: "Choose an inference provider:",
    choices,
    theme,
  });
}

export async function selectModel(models: string[], provider: string): Promise<string> {
  if (models.length === 0) {
    return input({
      message: `Enter model name for ${provider}:`,
      validate: (v) => (v.trim().length > 0 ? true : "Model name is required"),
      theme,
    });
  }

  const choices = [
    ...models.map((m) => ({ value: m, name: m })),
    { value: "__custom__", name: "Enter a custom model name" },
  ];

  const selected = await select({ message: "Choose a model:", choices, theme });
  if (selected === "__custom__") {
    return input({
      message: "Enter model name:",
      validate: (v) => (v.trim().length > 0 ? true : "Model name is required"),
      theme,
    });
  }
  return selected;
}

export async function promptApiKey(envKey: string): Promise<string> {
  return input({
    message: `Enter your API key (${envKey}):`,
    validate: (v) => (v.trim().length > 0 ? true : "API key is required"),
    theme,
  });
}

export async function promptBaseUrl(): Promise<string> {
  return input({
    message: "Enter the base URL (e.g. http://localhost:8000/v1):",
    validate: (v) => {
      if (!v.trim()) return "URL is required";
      try {
        new URL(v);
        return true;
      } catch {
        return "Invalid URL";
      }
    },
    theme,
  });
}

export async function selectTier(
  tiers: { value: string; name: string; description: string }[]
): Promise<string> {
  return select({
    message: "Choose a policy tier:",
    choices: tiers.map((t) => ({
      value: t.value,
      name: `${t.name} — ${t.description}`,
    })),
    theme,
  });
}

export async function selectPresets(
  available: { value: string; name: string }[],
  defaults: string[]
): Promise<string[]> {
  return checkbox({
    message: "Select policy presets (space to toggle, enter to confirm):",
    choices: available.map((p) => ({
      value: p.value,
      name: p.name,
      checked: defaults.includes(p.value),
    })),
    theme,
  });
}

export async function promptSandboxName(defaultName: string): Promise<string> {
  const name = await input({
    message: `Name your sandbox [${defaultName}]:`,
    default: defaultName,
    validate: (v) => {
      const n = v.trim().toLowerCase();
      if (!n) return "Name is required";
      if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(n)) {
        return "Use lowercase alphanumeric and hyphens, start/end with alphanumeric";
      }
      const reserved = /^(help|version|onboard|list|backup-all|doctor|uninstall|tunnel|status|destroy|debug)$/;
      if (reserved.test(n)) return `Name '${n}' is reserved`;
      return true;
    },
    theme,
  });
  return name.trim().toLowerCase();
}

export async function confirmAction(message: string, defaultYes = true): Promise<boolean> {
  return confirm({ message, default: defaultYes, theme });
}

export function printSummary(sandbox: string, model: string, tier: string): void {
  console.log("");
  console.log("─".repeat(50));
  console.log(`  Sandbox      ${chalk.cyan(sandbox)} (Landlock + seccomp + netns)`);
  console.log(`  Model        ${chalk.cyan(model)}`);
  console.log(`  Policy       ${chalk.cyan(tier)}`);
  console.log("─".repeat(50));
  console.log(`  Run:         ${chalk.cyan(`hermesclaw ${sandbox} connect`)}`);
  console.log(`  Status:      ${chalk.cyan(`hermesclaw ${sandbox} status`)}`);
  console.log(`  Logs:        ${chalk.cyan(`hermesclaw ${sandbox} logs --follow`)}`);
  console.log("─".repeat(50));
  console.log("");
  console.log(chalk.green("  [INFO]  === Onboarding complete ==="));
  console.log("");
}
