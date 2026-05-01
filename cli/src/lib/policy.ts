import { readFile, writeFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parse as parseYaml, stringify as stringifyYaml } from "yaml";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OPENSHELL_DIR = join(__dirname, "../../../openshell");

export interface PolicyTier {
  name: string;
  description: string;
  presets: string[];
}

export const POLICY_TIERS: PolicyTier[] = [
  {
    name: "restricted",
    description: "Base sandbox only. No third-party network access beyond inference.",
    presets: [],
  },
  {
    name: "balanced",
    description: "Full dev tooling and web search. No messaging platform access.",
    presets: ["npm", "pypi", "huggingface", "brave", "github"],
  },
  {
    name: "open",
    description: "Broad access across third-party services including messaging.",
    presets: ["npm", "pypi", "huggingface", "brave", "github", "slack", "discord", "telegram"],
  },
];

export const AVAILABLE_PRESETS = [
  { id: "telegram", name: "Telegram Bot API" },
  { id: "discord", name: "Discord (API + Gateway + CDN)" },
  { id: "slack", name: "Slack (API + WebSocket)" },
  { id: "github", name: "GitHub + API + raw content" },
  { id: "huggingface", name: "Hugging Face Hub + LFS" },
  { id: "brave", name: "Brave Search API" },
  { id: "npm", name: "npm / Yarn registries" },
  { id: "pypi", name: "Python Package Index" },
];

export function getTier(name: string): PolicyTier | undefined {
  return POLICY_TIERS.find((t) => t.name === name);
}

export function getBaselinePolicyPath(): string {
  return join(OPENSHELL_DIR, "baseline.yaml");
}

export function getPresetPath(preset: string): string {
  return join(OPENSHELL_DIR, "presets", `${preset}.yaml`);
}

export async function loadPolicyFile(path: string): Promise<any> {
  const content = await readFile(path, "utf-8");
  return parseYaml(content);
}

export async function assemblePolicyFile(
  presets: string[],
  outputPath: string
): Promise<void> {
  const baselinePath = getBaselinePolicyPath();
  const baseline = await loadPolicyFile(baselinePath);

  for (const preset of presets) {
    const presetPath = getPresetPath(preset);
    if (!existsSync(presetPath)) continue;
    const presetPolicy = await loadPolicyFile(presetPath);
    if (presetPolicy.network_policies) {
      baseline.network_policies = {
        ...baseline.network_policies,
        ...presetPolicy.network_policies,
      };
    }
  }

  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, stringifyYaml(baseline));
}
