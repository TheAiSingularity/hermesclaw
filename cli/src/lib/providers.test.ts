import { describe, it, expect } from "vitest";
import { PROVIDERS, getProvider, getProviderChoices } from "./providers.js";

describe("providers", () => {
  it("should have all required providers", () => {
    const ids = PROVIDERS.map((p) => p.id);
    expect(ids).toContain("nvidia");
    expect(ids).toContain("openai");
    expect(ids).toContain("anthropic");
    expect(ids).toContain("gemini");
    expect(ids).toContain("ollama");
    expect(ids).toContain("compatible");
    expect(ids).toContain("anthropic-compatible");
  });

  it("should return provider by id", () => {
    const nvidia = getProvider("nvidia");
    expect(nvidia).toBeDefined();
    expect(nvidia!.name).toBe("NVIDIA Endpoints");
    expect(nvidia!.envKey).toBe("NVIDIA_API_KEY");
    expect(nvidia!.models.length).toBeGreaterThan(0);
  });

  it("should return undefined for unknown provider", () => {
    expect(getProvider("nonexistent")).toBeUndefined();
  });

  it("should produce choices without experimental providers", () => {
    const choices = getProviderChoices();
    expect(choices.length).toBeGreaterThan(0);
    for (const choice of choices) {
      const provider = getProvider(choice.value);
      expect(provider!.experimental).toBeFalsy();
    }
  });

  it("nvidia provider should require API key but not base URL", () => {
    const nvidia = getProvider("nvidia")!;
    expect(nvidia.requiresApiKey).toBe(true);
    expect(nvidia.requiresBaseUrl).toBe(false);
    expect(nvidia.defaultBaseUrl).toBeDefined();
  });

  it("compatible provider should require both API key and base URL", () => {
    const compat = getProvider("compatible")!;
    expect(compat.requiresApiKey).toBe(true);
    expect(compat.requiresBaseUrl).toBe(true);
    expect(compat.models).toEqual([]);
  });

  it("ollama should not require API key", () => {
    const ollama = getProvider("ollama")!;
    expect(ollama.requiresApiKey).toBe(false);
    expect(ollama.endpointType).toBe("ollama");
  });
});
