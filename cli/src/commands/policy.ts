import chalk from "chalk";
import { select, confirm } from "@inquirer/prompts";
import { registryGet } from "../lib/registry.js";
import { loadRegistry, saveRegistry } from "../lib/registry.js";
import { AVAILABLE_PRESETS, getPresetPath, assemblePolicyFile } from "../lib/policy.js";
import { exec } from "../lib/exec.js";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { HERMESCLAW_HOME } from "../lib/constants.js";

async function policyAdd(name: string, opts: { dryRun?: boolean }): Promise<void> {
  const entry = await registryGet(name);
  if (!entry) {
    console.error(chalk.red(`Sandbox '${name}' not found.`));
    process.exit(1);
  }

  const currentPresets = entry.presets ?? [];
  const available = AVAILABLE_PRESETS.filter((p) => !currentPresets.includes(p.id));

  if (available.length === 0) {
    console.log(chalk.dim("All presets are already applied."));
    return;
  }

  const preset = await select({
    message: "Add a preset:",
    choices: available.map((p) => ({ value: p.id, name: p.name })),
  });

  const presetPath = getPresetPath(preset);
  if (!existsSync(presetPath)) {
    console.error(chalk.red(`Preset file not found: ${presetPath}`));
    process.exit(1);
  }

  if (opts.dryRun) {
    console.log(chalk.dim(`  Would add preset '${preset}' to sandbox '${name}'`));
    return;
  }

  // Apply dynamically
  const { exitCode, stderr } = await exec("openshell", [
    "policy", "set", "--policy", presetPath, name,
  ]);

  if (exitCode !== 0) {
    console.error(chalk.red(`Failed to apply preset: ${stderr}`));
    process.exit(1);
  }

  // Update registry
  const registry = await loadRegistry();
  if (registry.sandboxes[name]) {
    registry.sandboxes[name].presets = [...currentPresets, preset];
    await saveRegistry(registry);
  }

  console.log(chalk.green(`✓ Preset '${preset}' applied to '${name}'.`));
}

async function policyList(name: string): Promise<void> {
  const entry = await registryGet(name);
  if (!entry) {
    console.error(chalk.red(`Sandbox '${name}' not found.`));
    process.exit(1);
  }

  const currentPresets = entry.presets ?? [];

  console.log("");
  console.log(chalk.bold(`Policy Presets for: ${name}`));
  console.log("─".repeat(50));

  for (const preset of AVAILABLE_PRESETS) {
    const applied = currentPresets.includes(preset.id);
    const icon = applied ? chalk.green("✓") : chalk.dim("○");
    console.log(`  ${icon} ${preset.name} (${preset.id})`);
  }
  console.log("");
}

async function policyRemove(name: string, opts: { dryRun?: boolean }): Promise<void> {
  const entry = await registryGet(name);
  if (!entry) {
    console.error(chalk.red(`Sandbox '${name}' not found.`));
    process.exit(1);
  }

  const currentPresets = entry.presets ?? [];
  if (currentPresets.length === 0) {
    console.log(chalk.dim("No presets applied to this sandbox."));
    return;
  }

  const preset = await select({
    message: "Remove a preset:",
    choices: currentPresets.map((id) => {
      const p = AVAILABLE_PRESETS.find((a) => a.id === id);
      return { value: id, name: p?.name ?? id };
    }),
  });

  if (opts.dryRun) {
    console.log(chalk.dim(`  Would remove preset '${preset}' from sandbox '${name}'`));
    return;
  }

  // Reassemble policy without the removed preset
  const newPresets = currentPresets.filter((p) => p !== preset);
  const policyOutputPath = join(HERMESCLAW_HOME, "active-policy.yaml");
  await assemblePolicyFile(newPresets, policyOutputPath);

  const { exitCode, stderr } = await exec("openshell", [
    "policy", "set", "--policy", policyOutputPath, name,
  ]);

  if (exitCode !== 0) {
    console.error(chalk.red(`Failed to update policy: ${stderr}`));
    process.exit(1);
  }

  // Update registry
  const registry = await loadRegistry();
  if (registry.sandboxes[name]) {
    registry.sandboxes[name].presets = newPresets;
    await saveRegistry(registry);
  }

  console.log(chalk.green(`✓ Preset '${preset}' removed from '${name}'.`));
}

export const policyCommand = {
  add: policyAdd,
  list: policyList,
  remove: policyRemove,
};
