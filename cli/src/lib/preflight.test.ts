import { describe, it, expect, vi } from "vitest";

describe("preflight", () => {
  it("should compare versions correctly", async () => {
    // Test the version comparison logic inline since it's not exported
    function compareVersions(a: string, b: string): number {
      const pa = a.split(".").map(Number);
      const pb = b.split(".").map(Number);
      for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        const na = pa[i] ?? 0;
        const nb = pb[i] ?? 0;
        if (na !== nb) return na - nb;
      }
      return 0;
    }

    expect(compareVersions("0.8.0", "0.8.0")).toBe(0);
    expect(compareVersions("0.7.0", "0.8.0")).toBeLessThan(0);
    expect(compareVersions("1.0.0", "0.8.0")).toBeGreaterThan(0);
    expect(compareVersions("2.0.0", "2.0.0")).toBe(0);
    expect(compareVersions("1.2.3", "1.2.4")).toBeLessThan(0);
  });

  it("preflightPassed returns false when errors present", async () => {
    const { preflightPassed } = await import("./preflight.js");
    expect(preflightPassed({ docker: true, openshell: true, openshellVersion: "1.0.0", podman: false, errors: ["fail"], warnings: [] })).toBe(false);
    expect(preflightPassed({ docker: true, openshell: true, openshellVersion: "1.0.0", podman: false, errors: [], warnings: ["warn"] })).toBe(true);
  });
});
