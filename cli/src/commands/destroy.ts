import chalk from "chalk";
import { confirm } from "@inquirer/prompts";
import { destroySandbox, isSandboxRunning } from "../lib/sandbox.js";
import { registryGet } from "../lib/registry.js";

export async function destroyCommand(name: string): Promise<void> {
  const entry = await registryGet(name);
  if (!entry) {
    console.error(chalk.red(`Sandbox '${name}' not found in registry.`));
    process.exit(1);
  }

  console.log(chalk.yellow(`⚠ This will permanently delete sandbox '${name}' and its volume.`));
  console.log(chalk.yellow("  Back up first with: hermesclaw " + name + " snapshot create"));
  console.log("");

  const confirmed = await confirm({
    message: `Destroy sandbox '${name}'?`,
    default: false,
  });

  if (!confirmed) {
    console.log("Aborted.");
    return;
  }

  const ok = await destroySandbox(name);
  if (ok) {
    console.log(chalk.green(`✓ Sandbox '${name}' destroyed.`));
  } else {
    console.error(chalk.red(`Failed to destroy sandbox '${name}'.`));
    process.exit(1);
  }
}
