import chalk from "chalk";
import { loadRegistry } from "../lib/registry.js";

export async function listCommand(): Promise<void> {
  const registry = await loadRegistry();
  const names = Object.keys(registry.sandboxes).sort();

  if (names.length === 0) {
    console.log(chalk.dim("No sandboxes registered. Run: hermesclaw onboard"));
    return;
  }

  console.log("");
  console.log(chalk.bold("Registered Sandboxes"));
  console.log("─".repeat(50));

  for (const name of names) {
    const entry = registry.sandboxes[name];
    const isDefault = registry.default === name;
    const marker = isDefault ? chalk.green(" (default)") : "";
    console.log(`  ${chalk.cyan(name)}${marker}`);
    console.log(`    Model:   ${entry.model ?? "unknown"}`);
    console.log(`    Provider: ${entry.provider ?? "unknown"}`);
    console.log(`    Tier:    ${entry.tier ?? entry.policy}`);
    if (entry.presets && entry.presets.length > 0) {
      console.log(`    Presets: ${entry.presets.join(", ")}`);
    }
  }
  console.log("");
}
