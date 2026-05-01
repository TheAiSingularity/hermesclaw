import { readFileSync, writeFileSync, existsSync, unlinkSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { getHermesclawHome } from "./constants.js";
import { acquireLock, releaseLock } from "./lock.js";

export type StepStatus = "pending" | "in_progress" | "complete" | "failed" | "skipped";

export interface StepState {
  status: StepStatus;
  updatedAt?: string;
}

export type StepName =
  | "preflight"
  | "provider_selection"
  | "credentials"
  | "model_selection"
  | "validation"
  | "policy"
  | "sandbox_name"
  | "sandbox_create";

const ALL_STEPS: StepName[] = [
  "preflight",
  "provider_selection",
  "credentials",
  "model_selection",
  "validation",
  "policy",
  "sandbox_name",
  "sandbox_create",
];

export interface OnboardSession {
  version: number;
  sessionId: string;
  resumable: boolean;
  createdAt: string;
  updatedAt: string;
  provider?: string;
  model?: string;
  baseUrl?: string;
  apiPath?: string;
  tier?: string;
  presets?: string[];
  sandboxName?: string;
  dockerfilePath?: string;
  steps: Record<StepName, StepState>;
}

function getSessionDir(): string {
  return getHermesclawHome();
}

function getSessionFile(): string {
  return join(getSessionDir(), "onboard-session.json");
}

function getLockFile(): string {
  return join(getSessionDir(), "onboard.lock");
}

function defaultSteps(): Record<StepName, StepState> {
  const steps: Partial<Record<StepName, StepState>> = {};
  for (const s of ALL_STEPS) {
    steps[s] = { status: "pending" };
  }
  return steps as Record<StepName, StepState>;
}

export function createSession(): OnboardSession {
  const now = new Date().toISOString();
  return {
    version: 1,
    sessionId: randomUUID(),
    resumable: true,
    createdAt: now,
    updatedAt: now,
    steps: defaultSteps(),
  };
}

export function loadSession(): OnboardSession | null {
  const file = getSessionFile();
  if (!existsSync(file)) return null;
  try {
    const data = JSON.parse(readFileSync(file, "utf-8"));
    if (!data.steps) return null;
    // Ensure all step names exist (forward compatibility)
    for (const s of ALL_STEPS) {
      if (!data.steps[s]) data.steps[s] = { status: "pending" };
    }
    return data as OnboardSession;
  } catch {
    return null;
  }
}

export function saveSession(session: OnboardSession): void {
  const dir = getSessionDir();
  mkdirSync(dir, { recursive: true });
  session.updatedAt = new Date().toISOString();
  writeFileSync(getSessionFile(), JSON.stringify(session, null, 2));
}

export function clearSession(): void {
  const file = getSessionFile();
  if (existsSync(file)) {
    try { unlinkSync(file); } catch { /* best effort */ }
  }
}

export function markStep(session: OnboardSession, step: StepName, status: StepStatus): void {
  session.steps[step] = { status, updatedAt: new Date().toISOString() };
}

export function isStepComplete(session: OnboardSession, step: StepName): boolean {
  return session.steps[step]?.status === "complete";
}

export function completeSession(session: OnboardSession): void {
  session.resumable = false;
  saveSession(session);
}

export function acquireOnboardLock(): boolean {
  mkdirSync(getSessionDir(), { recursive: true });
  return acquireLock(getLockFile());
}

export function releaseOnboardLock(): void {
  releaseLock(getLockFile());
}
