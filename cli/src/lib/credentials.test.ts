import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  setCredential,
  getCredential,
  listCredentialKeys,
  removeCredential,
} from "./credentials.js";
import { getCredentialsFile } from "./constants.js";

let testDir: string;

describe("credentials", () => {
  beforeEach(async () => {
    testDir = await mkdtemp(join(tmpdir(), "hermesclaw-cred-test-"));
    process.env.HERMESCLAW_HOME = testDir;
  });

  afterEach(async () => {
    await rm(testDir, { recursive: true, force: true });
    delete process.env.HERMESCLAW_HOME;
  });

  it("should store and retrieve credentials", async () => {
    await setCredential("NVIDIA_API_KEY", "nvapi-test123");
    const value = await getCredential("NVIDIA_API_KEY");
    expect(value).toBe("nvapi-test123");
  });

  it("should list credential keys without values", async () => {
    await setCredential("KEY_A", "secret-a");
    await setCredential("KEY_B", "secret-b");

    const keys = await listCredentialKeys();
    expect(keys).toContain("KEY_A");
    expect(keys).toContain("KEY_B");
  });

  it("should remove credentials", async () => {
    await setCredential("TEMP_KEY", "temp-value");
    const removed = await removeCredential("TEMP_KEY");
    expect(removed).toBe(true);

    const value = await getCredential("TEMP_KEY");
    expect(value).toBeUndefined();
  });

  it("should return false when removing nonexistent key", async () => {
    const removed = await removeCredential("NOPE");
    expect(removed).toBe(false);
  });

  it("should set file permissions to 600", async () => {
    await setCredential("TEST", "value");

    const credFile = getCredentialsFile();
    const st = await stat(credFile);
    const mode = (st.mode & 0o777).toString(8);
    expect(mode).toBe("600");
  });
});
