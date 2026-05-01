#!/usr/bin/env node
import { Command } from "commander";
import { onboardCommand } from "./commands/onboard.js";
import { statusCommand } from "./commands/status.js";
import { connectCommand } from "./commands/connect.js";
import { logsCommand } from "./commands/logs.js";
import { destroyCommand } from "./commands/destroy.js";
import { listCommand } from "./commands/list.js";
import { backupAllCommand } from "./commands/backup-all.js";
import { doctorCommand } from "./commands/doctor.js";
import { uninstallCommand } from "./commands/uninstall.js";
import { credentialsCommand } from "./commands/credentials.js";
import { policyCommand } from "./commands/policy.js";
import { snapshotCommand } from "./commands/snapshot.js";
import { rebuildCommand } from "./commands/rebuild.js";
import { chatCommand } from "./commands/chat.js";
import { resolveDefaultSandbox } from "./lib/registry.js";

const VERSION = "0.0.50";

const program = new Command();

program
  .name("hermesclaw")
  .description("HermesClaw — Hermes Agent in NVIDIA OpenShell")
  .version(VERSION);

program
  .command("onboard")
  .description("Run the interactive setup wizard")
  .option("--non-interactive", "Run without prompts using env vars")
  .option("--resume", "Resume previous onboard session (skip completed steps)")
  .option("--fresh", "Discard any interrupted session and start over")
  .option("--recreate-sandbox", "Destroy and recreate the sandbox")
  .option("--from <dockerfile>", "Build from a custom Dockerfile")
  .option("--agent <name>", "Agent name for the sandbox")
  .option("--yes-i-accept-third-party-software", "Accept third-party notice")
  .action(onboardCommand);

program
  .command("list")
  .description("List all registered sandboxes")
  .action(listCommand);

program
  .command("backup-all")
  .description("Snapshot every registered sandbox")
  .action(backupAllCommand);

program
  .command("doctor")
  .description("Run end-to-end diagnostics")
  .option("--quick", "Skip slow checks (chat smoke test, DNS probe)")
  .action(doctorCommand);

program
  .command("uninstall")
  .description("Remove HermesClaw")
  .option("--yes", "Skip confirmation prompt")
  .option("--keep-openshell", "Leave openshell binary installed")
  .option("--delete-models", "Remove pulled Ollama models")
  .action(uninstallCommand);

program
  .command("credentials")
  .description("Manage stored credentials")
  .addCommand(
    new Command("list").description("List stored credential keys").action(credentialsCommand.list)
  )
  .addCommand(
    new Command("reset")
      .description("Remove a stored credential")
      .argument("<key>", "Credential key to remove")
      .option("--yes, -y", "Skip confirmation")
      .action(credentialsCommand.reset)
  );

// --- Sandbox commands ---
// Canonical syntax: hermesclaw <name> <command>
// Name-after syntax also works (Commander routing) but help shows name-first.

async function requireSandboxName(name?: string): Promise<string> {
  if (name) return name;
  const def = await resolveDefaultSandbox();
  if (def) return def;
  console.error("No default sandbox. Run: hermesclaw onboard");
  process.exit(1);
}

program
  .command("connect [name]", { hidden: true })
  .description("Open an interactive shell inside the sandbox")
  .action(async (name?: string) => {
    await connectCommand(await requireSandboxName(name));
  });

program
  .command("status [name]", { hidden: true })
  .description("Show sandbox health and inference config")
  .action(async (name?: string) => {
    await statusCommand(await requireSandboxName(name));
  });

program
  .command("logs [name]", { hidden: true })
  .description("View sandbox logs")
  .option("--follow", "Stream logs in real time")
  .action(async (name: string | undefined, opts: { follow?: boolean }) => {
    await logsCommand(await requireSandboxName(name), opts);
  });

program
  .command("destroy [name]", { hidden: true })
  .description("Permanently delete the sandbox")
  .action(async (name?: string) => {
    await destroyCommand(await requireSandboxName(name));
  });

program
  .command("chat <message> [name]", { hidden: true })
  .description("Send a one-shot message to Hermes")
  .action(async (message: string, name?: string) => {
    await chatCommand(await requireSandboxName(name), message);
  });

program
  .command("rebuild [name]", { hidden: true })
  .description("Snapshot, destroy, recreate, restore")
  .option("--yes", "Skip confirmation")
  .option("--verbose", "Log details")
  .action(async (name: string | undefined, opts: { yes?: boolean; verbose?: boolean }) => {
    await rebuildCommand(await requireSandboxName(name), opts);
  });

// Policy subcommands (hidden from top-level help; shown in custom section)
const policyCmd = program
  .command("policy", { hidden: true })
  .description("Manage sandbox policies");

policyCmd
  .command("add [name]")
  .description("Add a policy preset to the sandbox")
  .option("--dry-run", "Preview without applying")
  .action(async (name: string | undefined, opts: { dryRun?: boolean }) => {
    await policyCommand.add(await requireSandboxName(name), opts);
  });

policyCmd
  .command("list [name]")
  .description("List available and applied policy presets")
  .action(async (name?: string) => {
    await policyCommand.list(await requireSandboxName(name));
  });

policyCmd
  .command("remove [name]")
  .description("Remove a policy preset from the sandbox")
  .option("--dry-run", "Preview without applying")
  .action(async (name: string | undefined, opts: { dryRun?: boolean }) => {
    await policyCommand.remove(await requireSandboxName(name), opts);
  });

// Snapshot subcommands (hidden from top-level help; shown in custom section)
const snapshotCmd = program
  .command("snapshot", { hidden: true })
  .description("Manage point-in-time snapshots");

snapshotCmd
  .command("create [name]")
  .description("Create a snapshot of the sandbox")
  .action(async (name?: string) => {
    await snapshotCommand.create(await requireSandboxName(name));
  });

snapshotCmd
  .command("list [name]")
  .description("List snapshots for the sandbox")
  .action(async (name?: string) => {
    await snapshotCommand.list(await requireSandboxName(name));
  });

snapshotCmd
  .command("restore [name]")
  .description("Restore from a snapshot")
  .argument("[prefix]", "Timestamp prefix")
  .action(async (name: string | undefined, prefix?: string) => {
    await snapshotCommand.restore(await requireSandboxName(name), prefix);
  });

program.addHelpText("after", `
Sandbox commands (hermesclaw <name> ...):
  <name> connect                  Open an interactive shell
  <name> status                   Show sandbox health and inference config
  <name> logs [--follow]          View sandbox logs
  <name> destroy                  Permanently delete the sandbox
  <name> chat <message>           Send a one-shot message to Hermes
  <name> rebuild [--yes]          Snapshot, destroy, recreate, restore
  <name> policy add [--dry-run]   Add a policy preset
  <name> policy list              List available and applied presets
  <name> policy remove [--dry-run] Remove a policy preset
  <name> snapshot create          Create a point-in-time snapshot
  <name> snapshot list            List snapshots
  <name> snapshot restore [prefix] Restore from a snapshot
`);

// Also support `hermesclaw <name> <command>` syntax (NemoClaw compat)
const SANDBOX_COMMANDS = [
  "status", "connect", "logs", "destroy",
  "policy", "snapshot", "rebuild", "chat",
];

program.on("command:*", async (operands: string[]) => {
  const [nameOrCmd, ...rest] = operands;
  if (rest.length > 0 && SANDBOX_COMMANDS.includes(rest[0])) {
    process.argv = ["node", "hermesclaw", rest[0], ...rest.slice(1), nameOrCmd];
    await program.parseAsync(process.argv);
  } else {
    console.error(`Unknown command: ${nameOrCmd}`);
    program.help();
  }
});

program.parseAsync().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
