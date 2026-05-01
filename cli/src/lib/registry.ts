import { readFile, writeFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { getHermesclawHome, getRegistryFile } from "./constants.js";
import { acquireLock, releaseLock } from "./lock.js";

export interface SandboxEntry {
  created: string;
  policy: string;
  profile: string;
  provider?: string;
  model?: string;
  tier?: string;
  presets?: string[];
}

export interface Registry {
  default: string;
  sandboxes: Record<string, SandboxEntry>;
}

function getLockPath(): string {
  return join(getHermesclawHome(), ".sandboxes.json.lock");
}

async function ensureRegistry(): Promise<void> {
  await mkdir(getHermesclawHome(), { recursive: true });
  if (!existsSync(getRegistryFile())) {
    const empty: Registry = { default: "", sandboxes: {} };
    await writeFile(getRegistryFile(), JSON.stringify(empty, null, 2));
  }
}

export async function loadRegistry(): Promise<Registry> {
  await ensureRegistry();
  const data = await readFile(getRegistryFile(), "utf-8");
  return JSON.parse(data);
}

export async function saveRegistry(registry: Registry): Promise<void> {
  await ensureRegistry();
  const lockPath = getLockPath();
  const locked = acquireLock(lockPath);
  try {
    await writeFile(getRegistryFile(), JSON.stringify(registry, null, 2));
  } finally {
    if (locked) releaseLock(lockPath);
  }
}

export async function registryAdd(
  name: string,
  entry: Omit<SandboxEntry, "created">
): Promise<void> {
  const registry = await loadRegistry();
  registry.sandboxes[name] = {
    created: new Date().toISOString(),
    ...entry,
  };
  registry.default = name;
  await saveRegistry(registry);
}

export async function registryRemove(name: string): Promise<void> {
  const registry = await loadRegistry();
  delete registry.sandboxes[name];
  if (registry.default === name) {
    const names = Object.keys(registry.sandboxes);
    registry.default = names[0] ?? "";
  }
  await saveRegistry(registry);
}

export async function registryList(): Promise<string[]> {
  const registry = await loadRegistry();
  return Object.keys(registry.sandboxes).sort();
}

export async function registryGet(name: string): Promise<SandboxEntry | undefined> {
  const registry = await loadRegistry();
  return registry.sandboxes[name];
}

export async function resolveDefaultSandbox(): Promise<string | null> {
  const registry = await loadRegistry();
  return registry.default || null;
}

export async function setDefaultSandbox(name: string): Promise<void> {
  const registry = await loadRegistry();
  registry.default = name;
  await saveRegistry(registry);
}
