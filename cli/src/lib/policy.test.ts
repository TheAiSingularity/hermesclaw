import { describe, it, expect } from "vitest";
import { POLICY_TIERS, AVAILABLE_PRESETS, getTier } from "./policy.js";

describe("policy", () => {
  it("should have three tiers", () => {
    expect(POLICY_TIERS.length).toBe(3);
    const names = POLICY_TIERS.map((t) => t.name);
    expect(names).toContain("restricted");
    expect(names).toContain("balanced");
    expect(names).toContain("open");
  });

  it("restricted tier should have no presets", () => {
    const tier = getTier("restricted");
    expect(tier).toBeDefined();
    expect(tier!.presets).toEqual([]);
  });

  it("balanced tier should include dev tooling presets", () => {
    const tier = getTier("balanced")!;
    expect(tier.presets).toContain("npm");
    expect(tier.presets).toContain("pypi");
    expect(tier.presets).toContain("github");
    expect(tier.presets).not.toContain("telegram");
    expect(tier.presets).not.toContain("slack");
  });

  it("open tier should include messaging presets", () => {
    const tier = getTier("open")!;
    expect(tier.presets).toContain("slack");
    expect(tier.presets).toContain("discord");
    expect(tier.presets).toContain("telegram");
  });

  it("should have all expected presets available", () => {
    const ids = AVAILABLE_PRESETS.map((p) => p.id);
    expect(ids).toContain("telegram");
    expect(ids).toContain("discord");
    expect(ids).toContain("slack");
    expect(ids).toContain("github");
    expect(ids).toContain("huggingface");
    expect(ids).toContain("brave");
    expect(ids).toContain("npm");
    expect(ids).toContain("pypi");
  });

  it("getTier returns undefined for unknown tier", () => {
    expect(getTier("nonexistent")).toBeUndefined();
  });
});
