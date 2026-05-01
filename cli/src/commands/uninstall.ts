import chalk from "chalk";
import { confirm } from "@inquirer/prompts";
import { exec } from "../lib/exec.js";
import { registryList } from "../lib/registry.js";
import { destroySandbox, isSandboxRunning } from "../lib/sandbox.js";
import { HERMESCLAW_HOME } from "../lib/constants.js";
import { rm } from "node:fs/promises";

interface UninstallOptions {
  yes?: boolean;
  keepOpenshell?: boolean;
  deleteModels?: boolean;
}

export async function uninstallCommand(opts: UninstallOptions): Promise<void> {
  console.log("");
  console.log(chalk.bold("HermesClaw Uninstall"));
  console.log("─".repeat(50));

  if (!opts.yes) {
    console.log(chalk.yellow("This will remove all HermesClaw sandboxes and local state."));
    console.log(chalk.dim("  Memories preserved: ~/.hermes/"));
    console.log("");
    const confirmed = await confirm({
      message: "Proceed with uninstall?",
      default: false,
    });
    if (!confirmed) {
      console.log("Aborted.");
      return;
    }
  }

  // Destroy all sandboxes
  const names = await registryList();
  for (const name of names) {
    if (await isSandboxRunning(name)) {
      console.log(`  Destroying sandbox: ${name}`);
      await destroySandbox(name);
    }
  }

  // Remove Docker image
  await exec("docker", ["rmi", "hermesclaw:latest"]);
  console.log("  Docker image hermesclaw:latest removed.");

  // Remove state directory
  await rm(HERMESCLAW_HOME, { recursive: true, force: true });
  console.log(`  Removed ${HERMESCLAW_HOME}`);

  if (opts.deleteModels) {
    console.log("  Removing Ollama models pulled by HermesClaw...");
    await exec("ollama", ["rm", "hermesclaw-default"]);
  }

  if (!opts.keepOpenshell) {
    console.log("  Removing OpenShell...");
    const { exitCode } = await exec("openshell", ["gateway", "destroy"]);
    if (exitCode === 0) {
      console.log("  OpenShell gateway destroyed.");
    }
  } else {
    console.log(chalk.dim("  Keeping OpenShell (--keep-openshell)."));
  }

  console.log("");
  console.log(chalk.green("HermesClaw uninstalled."));
  console.log(chalk.dim("Memories preserved: ~/.hermes/"));
  console.log("");
}
