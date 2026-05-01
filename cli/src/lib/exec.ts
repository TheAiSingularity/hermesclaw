import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export interface ExecResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

export interface ExecOptions {
  timeout?: number;
}

export async function exec(
  command: string,
  args: string[] = [],
  opts: ExecOptions = {}
): Promise<ExecResult> {
  try {
    const { stdout, stderr } = await execFileAsync(command, args, {
      timeout: opts.timeout ?? 60_000,
      maxBuffer: 10 * 1024 * 1024,
    });
    return { stdout: stdout.trim(), stderr: stderr.trim(), exitCode: 0 };
  } catch (err: any) {
    return {
      stdout: err.stdout?.trim() ?? "",
      stderr: err.stderr?.trim() ?? "",
      exitCode: err.code ?? 1,
    };
  }
}

export function execStreaming(
  command: string,
  args: string[]
): Promise<ExecResult> {
  return new Promise((resolve) => {
    const chunks: string[] = [];
    const errChunks: string[] = [];
    const child = spawn(command, args, { stdio: ["inherit", "pipe", "pipe"] });
    child.stdout?.on("data", (d: Buffer) => {
      const s = d.toString();
      chunks.push(s);
      process.stdout.write(s);
    });
    child.stderr?.on("data", (d: Buffer) => {
      const s = d.toString();
      errChunks.push(s);
      process.stderr.write(s);
    });
    child.on("close", (code) => {
      resolve({
        stdout: chunks.join("").trim(),
        stderr: errChunks.join("").trim(),
        exitCode: code ?? 1,
      });
    });
  });
}

export async function hasCommand(name: string): Promise<boolean> {
  const { exitCode } = await exec("which", [name]);
  return exitCode === 0;
}

export function spawnInteractive(command: string, args: string[]): Promise<number> {
  return new Promise((resolve) => {
    const child = spawn(command, args, { stdio: "inherit" });
    child.on("close", (code) => resolve(code ?? 1));
  });
}
