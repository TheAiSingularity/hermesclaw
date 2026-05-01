const CREDENTIAL_PATTERNS = [
  /api[_-]?key/i,
  /secret/i,
  /token/i,
  /password/i,
  /credential/i,
  /authorization/i,
];

const SENSITIVE_BASENAMES = new Set([
  "credentials.json",
  ".env",
  ".env.local",
  ".env.production",
]);

export function isCredentialField(key: string): boolean {
  return CREDENTIAL_PATTERNS.some((p) => p.test(key));
}

export function isSensitiveFile(filename: string): boolean {
  const basename = filename.split("/").pop() ?? "";
  return SENSITIVE_BASENAMES.has(basename);
}

/**
 * Strip credential values from an object, replacing them with "[REDACTED]".
 * Only operates on string values whose keys match credential patterns.
 */
export function stripCredentials<T extends Record<string, unknown>>(obj: T): T {
  const result = { ...obj };
  for (const [key, value] of Object.entries(result)) {
    if (typeof value === "string" && isCredentialField(key)) {
      (result as Record<string, unknown>)[key] = "[REDACTED]";
    } else if (typeof value === "object" && value !== null && !Array.isArray(value)) {
      (result as Record<string, unknown>)[key] = stripCredentials(
        value as Record<string, unknown>
      );
    }
  }
  return result;
}

/**
 * Redact known credential patterns from a raw string (e.g., log output).
 * Replaces values that look like API keys / bearer tokens.
 */
export function redactString(text: string): string {
  return text
    .replace(/(Bearer\s+)[^\s"']+/gi, "$1[REDACTED]")
    .replace(/((?:api[_-]?key|token|secret|password)\s*[=:]\s*)[^\s"',}]+/gi, "$1[REDACTED]")
    .replace(/(nvapi-)[a-zA-Z0-9_-]+/g, "$1[REDACTED]")
    .replace(/(sk-)[a-zA-Z0-9_-]{20,}/g, "$1[REDACTED]");
}
