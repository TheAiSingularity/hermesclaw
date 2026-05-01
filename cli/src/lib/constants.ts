import { homedir } from "node:os";
import { join } from "node:path";

export function getHermesclawHome(): string {
  return process.env.HERMESCLAW_HOME || join(homedir(), ".hermesclaw");
}

export function getRegistryFile(): string {
  return join(getHermesclawHome(), "sandboxes.json");
}

export function getCredentialsFile(): string {
  return join(getHermesclawHome(), "credentials.json");
}

// Static aliases for use in non-test paths
export const HERMESCLAW_HOME = getHermesclawHome();
export const REGISTRY_FILE = getRegistryFile();
export const CREDENTIALS_FILE = getCredentialsFile();

export const MIN_OPENSHELL_VERSION = "0.0.30";
export const MAX_OPENSHELL_VERSION = "2.0.0";

export const HERMESCLAW_VERSION = "1.0.0";

export const DEFAULT_GATEWAY_PORT = 8080;
export const DEFAULT_DASHBOARD_PORT = 18789;
export const DEFAULT_OLLAMA_PORT = 11434;
