import chalk from "chalk";
import { connectToSandbox, isSandboxRunning } from "../lib/sandbox.js";

export async function connectCommand(name: string): Promise<void> {
  const running = await isSandboxRunning(name);
  if (!running) {
    console.error(chalk.red(`Sandbox '${name}' is not running.`));
    process.exit(1);
  }

  console.log(chalk.dim(`Connecting to ${name}... (run 'hermes tui' inside for the chat UI)`));
  await connectToSandbox(name);
}
