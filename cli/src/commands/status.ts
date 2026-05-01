import chalk from "chalk";
import { exec } from "../lib/exec.js";
import { registryGet } from "../lib/registry.js";

export async function statusCommand(name: string): Promise<void> {
  const entry = await registryGet(name);
  if (!entry) {
    console.error(chalk.red(`Sandbox '${name}' not found in registry.`));
    process.exit(1);
  }

  console.log("");
  console.log(chalk.bold(`Sandbox: ${name}`));
  console.log("─".repeat(50));

  // Check if running
  const { stdout: listOut } = await exec("openshell", ["sandbox", "list"]);
  const running = listOut.includes(name);
  console.log(`  Status:    ${running ? chalk.green("running") : chalk.yellow("stopped")}`);
  console.log(`  Provider:  ${chalk.cyan(entry.provider ?? "unknown")}`);
  console.log(`  Model:     ${chalk.cyan(entry.model ?? "unknown")}`);
  console.log(`  Tier:      ${chalk.cyan(entry.tier ?? entry.policy)}`);
  if (entry.presets && entry.presets.length > 0) {
    console.log(`  Presets:   ${chalk.cyan(entry.presets.join(", "))}`);
  }
  console.log(`  Created:   ${chalk.dim(entry.created)}`);

  // Probe inference health
  if (running) {
    const { exitCode } = await exec("openshell", ["inference", "get"]);
    if (exitCode === 0) {
      console.log(`  Inference: ${chalk.green("routed")}`);
    } else {
      console.log(`  Inference: ${chalk.yellow("unreachable")}`);
    }
  }

  console.log("");
}
