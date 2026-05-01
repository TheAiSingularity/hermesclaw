import { writeFileSync, readFileSync, unlinkSync, existsSync } from "node:fs";

const LOCK_STALE_MS = 30_000;

export function acquireLock(lockPath: string): boolean {
  if (existsSync(lockPath)) {
    try {
      const content = readFileSync(lockPath, "utf-8");
      const { pid, ts } = JSON.parse(content);
      // Stale if the owning process is dead or lock is older than threshold
      const alive = isProcessAlive(pid);
      const stale = Date.now() - ts > LOCK_STALE_MS;
      if (alive && !stale) return false;
    } catch { /* corrupt lock file — take it over */ }
  }
  writeFileSync(lockPath, JSON.stringify({ pid: process.pid, ts: Date.now() }));
  return true;
}

export function releaseLock(lockPath: string): void {
  try {
    if (!existsSync(lockPath)) return;
    const content = readFileSync(lockPath, "utf-8");
    const { pid } = JSON.parse(content);
    if (pid === process.pid) unlinkSync(lockPath);
  } catch { /* best effort */ }
}

export async function withLock<T>(lockPath: string, fn: () => Promise<T>): Promise<T> {
  if (!acquireLock(lockPath)) {
    throw new Error(`Another HermesClaw process holds the lock: ${lockPath}`);
  }
  try {
    return await fn();
  } finally {
    releaseLock(lockPath);
  }
}

function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}
