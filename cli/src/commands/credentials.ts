import chalk from "chalk";
import { confirm } from "@inquirer/prompts";
import { listCredentialKeys, removeCredential } from "../lib/credentials.js";

async function listCreds(): Promise<void> {
  const keys = await listCredentialKeys();
  if (keys.length === 0) {
    console.log(chalk.dim("No credentials stored."));
    return;
  }

  console.log("");
  console.log(chalk.bold("Stored Credentials"));
  console.log("─".repeat(50));
  for (const key of keys) {
    console.log(`  ${key}`);
  }
  console.log("");
  console.log(chalk.dim("Values are not displayed. Use 'hermesclaw credentials reset <KEY>' to remove."));
  console.log("");
}

async function resetCred(key: string, opts: { yes?: boolean }): Promise<void> {
  if (!opts.yes) {
    const confirmed = await confirm({
      message: `Remove stored credential '${key}'?`,
      default: false,
    });
    if (!confirmed) {
      console.log("Aborted.");
      return;
    }
  }

  const removed = await removeCredential(key);
  if (removed) {
    console.log(chalk.green(`✓ Credential '${key}' removed.`));
    console.log(chalk.dim("  Re-running 'hermesclaw onboard' will prompt for this key again."));
  } else {
    console.log(chalk.yellow(`Credential '${key}' not found.`));
  }
}

export const credentialsCommand = {
  list: listCreds,
  reset: resetCred,
};
