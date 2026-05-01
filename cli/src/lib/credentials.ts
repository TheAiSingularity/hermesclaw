import { readFile, writeFile, mkdir, chmod } from "node:fs/promises";
import { existsSync } from "node:fs";
import { getCredentialsFile, getHermesclawHome } from "./constants.js";

type Credentials = Record<string, string>;

async function ensureDir(): Promise<void> {
  await mkdir(getHermesclawHome(), { recursive: true });
}

export async function loadCredentials(): Promise<Credentials> {
  await ensureDir();
  const credFile = getCredentialsFile();
  if (!existsSync(credFile)) return {};
  const data = await readFile(credFile, "utf-8");
  return JSON.parse(data);
}

export async function saveCredentials(creds: Credentials): Promise<void> {
  await ensureDir();
  const credFile = getCredentialsFile();
  await writeFile(credFile, JSON.stringify(creds, null, 2));
  await chmod(credFile, 0o600);
}

export async function getCredential(key: string): Promise<string | undefined> {
  const creds = await loadCredentials();
  return creds[key];
}

export async function setCredential(key: string, value: string): Promise<void> {
  const creds = await loadCredentials();
  creds[key] = value;
  await saveCredentials(creds);
}

export async function removeCredential(key: string): Promise<boolean> {
  const creds = await loadCredentials();
  if (!(key in creds)) return false;
  delete creds[key];
  await saveCredentials(creds);
  return true;
}

export async function listCredentialKeys(): Promise<string[]> {
  const creds = await loadCredentials();
  return Object.keys(creds).sort();
}

export function resolveApiKey(envKey: string): string | undefined {
  return process.env[envKey];
}
