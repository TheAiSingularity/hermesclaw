import chalk from "chalk";
import { registryList } from "../lib/registry.js";
import { isSandboxRunning } from "../lib/sandbox.js";
import { snapshotCommand } from "./snapshot.js";

export async function backupAllCommand(): Promise<void> {
  const names = await registryList();
  if (names.length === 0) {
    console.log(chalk.dim("No sandboxes registered."));
    return;
  }

  console.log(chalk.bold("Backing up all running sandboxes..."));
  console.log("");

  for (const name of names) {
    const running = await isSandboxRunning(name);
    if (!running) {
      console.log(`  ${chalk.dim(name)} — skipped (not running)`);
      continue;
    }

    try {
      await snapshotCommand.create(name);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      console.log(`  ${chalk.red("✗")} ${name} — ${msg}`);
    }
  }

  console.log("");
}
