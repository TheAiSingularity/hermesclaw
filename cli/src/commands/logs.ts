import chalk from "chalk";
import { getSandboxLogs, isSandboxRunning } from "../lib/sandbox.js";

export async function logsCommand(
  name: string,
  opts: { follow?: boolean }
): Promise<void> {
  const running = await isSandboxRunning(name);
  if (!running) {
    console.error(chalk.red(`Sandbox '${name}' is not running.`));
    process.exit(1);
  }

  await getSandboxLogs(name, opts.follow ?? false);
}
