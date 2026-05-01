export interface ProviderDefinition {
  id: string;
  name: string;
  envKey: string;
  endpointType: "openai" | "anthropic" | "ollama";
  requiresApiKey: boolean;
  requiresBaseUrl: boolean;
  defaultBaseUrl?: string;
  models: string[];
  openshellProvider: string;
  /** The base URL OpenShell's L7 proxy should forward to (host-side address). */
  openshellBaseUrl?: string;
  /** OpenShell provider type (openai, nvidia, anthropic, etc.) */
  openshellType: string;
  experimental?: boolean;
  condition?: () => Promise<boolean>;
}

export const PROVIDERS: ProviderDefinition[] = [
  {
    id: "nvidia",
    name: "NVIDIA Endpoints",
    envKey: "NVIDIA_API_KEY",
    endpointType: "openai",
    requiresApiKey: true,
    requiresBaseUrl: false,
    defaultBaseUrl: "https://integrate.api.nvidia.com/v1",
    models: [
      "nvidia/nemotron-3-super-120b-a12b",
      "kimi-k2.5",
      "glm-5",
      "minimax-m2.5",
      "gpt-oss-120b",
    ],
    openshellProvider: "nvidia-prod",
    openshellType: "nvidia",
  },
  {
    id: "openai",
    name: "OpenAI",
    envKey: "OPENAI_API_KEY",
    endpointType: "openai",
    requiresApiKey: true,
    requiresBaseUrl: false,
    defaultBaseUrl: "https://api.openai.com/v1",
    models: ["gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano"],
    openshellProvider: "openai-api",
    openshellType: "openai",
  },
  {
    id: "compatible",
    name: "Other OpenAI-compatible endpoint",
    envKey: "COMPATIBLE_API_KEY",
    endpointType: "openai",
    requiresApiKey: true,
    requiresBaseUrl: true,
    models: [],
    openshellProvider: "compatible-endpoint",
    openshellType: "openai",
  },
  {
    id: "anthropic",
    name: "Anthropic",
    envKey: "ANTHROPIC_API_KEY",
    endpointType: "anthropic",
    requiresApiKey: true,
    requiresBaseUrl: false,
    defaultBaseUrl: "https://api.anthropic.com",
    models: ["claude-sonnet-4-6", "claude-haiku-4-5", "claude-opus-4-6"],
    openshellProvider: "anthropic-prod",
    openshellType: "openai",
  },
  {
    id: "anthropic-compatible",
    name: "Other Anthropic-compatible endpoint",
    envKey: "COMPATIBLE_ANTHROPIC_API_KEY",
    endpointType: "anthropic",
    requiresApiKey: true,
    requiresBaseUrl: true,
    models: [],
    openshellProvider: "compatible-anthropic-endpoint",
    openshellType: "openai",
  },
  {
    id: "gemini",
    name: "Google Gemini",
    envKey: "GEMINI_API_KEY",
    endpointType: "openai",
    requiresApiKey: true,
    requiresBaseUrl: false,
    defaultBaseUrl: "https://generativelanguage.googleapis.com/v1beta/openai",
    models: [
      "gemini-2.5-pro",
      "gemini-2.5-flash",
      "gemini-2.5-flash-lite",
    ],
    openshellProvider: "gemini-api",
    openshellType: "openai",
  },
  {
    id: "ollama",
    name: "Local Ollama",
    envKey: "",
    endpointType: "ollama",
    requiresApiKey: false,
    requiresBaseUrl: false,
    defaultBaseUrl: "http://localhost:11434",
    models: [],
    openshellProvider: "local-llama",
    openshellBaseUrl: "http://host.openshell.internal:11434/v1",
    openshellType: "openai",
  },
];

export function getProvider(id: string): ProviderDefinition | undefined {
  return PROVIDERS.find((p) => p.id === id);
}

export function getProviderChoices(): { value: string; name: string }[] {
  return PROVIDERS.filter((p) => !p.experimental).map((p) => ({
    value: p.id,
    name: p.name,
  }));
}
