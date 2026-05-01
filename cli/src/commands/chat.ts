import chalk from "chalk";
import { exec } from "../lib/exec.js";
import { isSandboxRunning } from "../lib/sandbox.js";
import { registryGet } from "../lib/registry.js";

export async function chatCommand(name: string, message: string): Promise<void> {
  const entry = await registryGet(name);
  if (!entry) {
    console.error(chalk.red(`Sandbox '${name}' not found.`));
    process.exit(1);
  }

  const running = await isSandboxRunning(name);
  if (!running) {
    console.error(chalk.red(`Sandbox '${name}' is not running.`));
    process.exit(1);
  }

  const { stdout, stderr, exitCode } = await exec("openshell", [
    "sandbox", "exec", name, "--",
    "hermes", "agent", "--agent", "main", "--local",
    "-m", message, "--session-id", `cli-${Date.now()}`,
  ]);

  if (exitCode !== 0) {
    console.error(chalk.red(`Chat failed: ${stderr}`));
    process.exit(1);
  }

  console.log(stdout);
}
