import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  loadRegistry,
  saveRegistry,
  registryAdd,
  registryRemove,
  registryList,
  registryGet,
} from "./registry.js";

let testDir: string;

describe("registry", () => {
  beforeEach(async () => {
    testDir = await mkdtemp(join(tmpdir(), "hermesclaw-test-"));
    process.env.HERMESCLAW_HOME = testDir;
  });

  afterEach(async () => {
    await rm(testDir, { recursive: true, force: true });
    delete process.env.HERMESCLAW_HOME;
  });

  it("should create registry on first load", async () => {
    const registry = await loadRegistry();
    expect(registry.default).toBe("");
    expect(registry.sandboxes).toEqual({});
  });

  it("should add and list sandboxes", async () => {
    await registryAdd("test-sandbox", {
      policy: "balanced",
      profile: "test-sandbox",
      provider: "openai",
      model: "gpt-5.4",
      tier: "balanced",
      presets: ["npm", "pypi"],
    });

    const names = await registryList();
    expect(names).toContain("test-sandbox");

    const registry = await loadRegistry();
    expect(registry.default).toBe("test-sandbox");
    expect(registry.sandboxes["test-sandbox"].provider).toBe("openai");
    expect(registry.sandboxes["test-sandbox"].model).toBe("gpt-5.4");
  });

  it("should remove sandboxes and update default", async () => {
    await registryAdd("sb-1", { policy: "strict", profile: "sb-1" });
    await registryAdd("sb-2", { policy: "open", profile: "sb-2" });

    // sb-2 is default (most recently added)
    const before = await loadRegistry();
    expect(before.default).toBe("sb-2");

    await registryRemove("sb-2");
    const registry = await loadRegistry();
    expect(registry.sandboxes["sb-2"]).toBeUndefined();
    expect(registry.default).toBe("sb-1");
  });

  it("should get a specific sandbox entry", async () => {
    await registryAdd("my-bot", {
      policy: "open",
      profile: "my-bot",
      provider: "anthropic",
      model: "claude-sonnet-4-6",
      tier: "open",
      presets: ["telegram", "discord"],
    });

    const entry = await registryGet("my-bot");
    expect(entry).toBeDefined();
    expect(entry!.provider).toBe("anthropic");
    expect(entry!.presets).toEqual(["telegram", "discord"]);

    const missing = await registryGet("nonexistent");
    expect(missing).toBeUndefined();
  });
});
