import chalk from "chalk";

export type FailureKind = "transport" | "credential" | "model" | "endpoint" | "unknown";
export type RetryHint = "retry" | "credential" | "model" | "selection";

export interface ValidationResult {
  valid: boolean;
  apiPath: "openai-completions" | "openai-responses" | "anthropic-messages";
  error?: string;
  failureKind?: FailureKind;
  retryHint?: RetryHint;
}

function classifyFailure(
  statusCode: number | null,
  errorMessage: string
): { kind: FailureKind; retry: RetryHint } {
  const msg = errorMessage.toLowerCase();

  if (msg.includes("econnrefused") || msg.includes("enotfound") ||
      msg.includes("etimedout") || msg.includes("fetch failed") ||
      msg.includes("network") || msg.includes("dns")) {
    return { kind: "transport", retry: "retry" };
  }

  if (statusCode === 401 || statusCode === 403 ||
      msg.includes("unauthorized") || msg.includes("invalid api key") ||
      msg.includes("forbidden") || msg.includes("authentication")) {
    return { kind: "credential", retry: "credential" };
  }

  if (statusCode === 404 || msg.includes("model not found") ||
      msg.includes("does not exist") || msg.includes("no such model")) {
    return { kind: "model", retry: "model" };
  }

  if (statusCode === 400 || statusCode === 422 ||
      msg.includes("invalid request") || msg.includes("bad request")) {
    return { kind: "endpoint", retry: "selection" };
  }

  return { kind: "unknown", retry: "retry" };
}

async function probeWithClassification(
  url: string,
  init: RequestInit,
  label: string,
): Promise<{ ok: boolean; status: number | null; error: string }> {
  try {
    const res = await fetch(url, init);
    if (res.ok) return { ok: true, status: res.status, error: "" };
    let body = "";
    try { body = await res.text(); } catch { /* ignore */ }
    return { ok: false, status: res.status, error: `${label}: HTTP ${res.status} — ${body.slice(0, 200)}` };
  } catch (err: any) {
    return { ok: false, status: null, error: `${label}: ${err.message}` };
  }
}

async function probeOpenAIResponses(
  baseUrl: string, apiKey: string, model: string,
): Promise<{ ok: boolean; status: number | null; error: string }> {
  const url = `${baseUrl.replace(/\/$/, "")}/responses`;
  return probeWithClassification(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({ model, input: "Say hello", max_output_tokens: 32 }),
    signal: AbortSignal.timeout(15_000),
  }, "Responses API");
}

async function probeOpenAICompletions(
  baseUrl: string, apiKey: string, model: string,
): Promise<{ ok: boolean; status: number | null; error: string }> {
  const url = `${baseUrl.replace(/\/$/, "")}/chat/completions`;
  return probeWithClassification(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({ model, messages: [{ role: "user", content: "Say hello" }], max_tokens: 32 }),
    signal: AbortSignal.timeout(15_000),
  }, "Completions API");
}

async function probeAnthropic(
  baseUrl: string, apiKey: string, model: string,
): Promise<{ ok: boolean; status: number | null; error: string }> {
  const url = `${baseUrl.replace(/\/$/, "")}/v1/messages`;
  return probeWithClassification(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({ model, max_tokens: 32, messages: [{ role: "user", content: "Say hello" }] }),
    signal: AbortSignal.timeout(15_000),
  }, "Anthropic Messages API");
}

async function probeOllama(baseUrl: string, model: string): Promise<ValidationResult> {
  const cleanUrl = baseUrl.replace(/\/$/, "");

  try {
    const pingRes = await fetch(cleanUrl, { signal: AbortSignal.timeout(5_000) });
    if (!pingRes.ok) {
      return {
        valid: false, apiPath: "openai-completions",
        error: `Ollama not reachable at ${cleanUrl} (HTTP ${pingRes.status})`,
        failureKind: "transport", retryHint: "retry",
      };
    }
  } catch (err: any) {
    return {
      valid: false, apiPath: "openai-completions",
      error: `Cannot reach Ollama at ${cleanUrl}: ${err.message}`,
      failureKind: "transport", retryHint: "retry",
    };
  }

  try {
    const tagsRes = await fetch(`${cleanUrl}/api/tags`, { signal: AbortSignal.timeout(5_000) });
    if (tagsRes.ok) {
      const data = (await tagsRes.json()) as any;
      const models: string[] = (data.models ?? []).map((m: any) => m.name);
      const found = models.some(
        (m) => m === model || m.startsWith(`${model}:`) || model.startsWith(`${m.split(":")[0]}:`)
      );
      if (!found && models.length > 0) {
        return {
          valid: false, apiPath: "openai-completions",
          error: `Model '${model}' not found in Ollama. Available: ${models.slice(0, 5).join(", ")}`,
          failureKind: "model", retryHint: "model",
        };
      }
    }
  } catch { /* tags endpoint optional */ }

  return { valid: true, apiPath: "openai-completions" };
}

export async function validateProvider(
  endpointType: "openai" | "anthropic" | "ollama",
  baseUrl: string,
  apiKey: string,
  model: string
): Promise<ValidationResult> {
  console.log(chalk.dim("  Validating inference endpoint..."));

  if (endpointType === "ollama") {
    return probeOllama(baseUrl, model);
  }

  if (endpointType === "anthropic") {
    const result = await probeAnthropic(baseUrl, apiKey, model);
    if (result.ok) return { valid: true, apiPath: "anthropic-messages" };
    const { kind, retry } = classifyFailure(result.status, result.error);
    return {
      valid: false, apiPath: "anthropic-messages",
      error: result.error, failureKind: kind, retryHint: retry,
    };
  }

  // OpenAI-compatible
  const preferredApi = process.env.HERMESCLAW_PREFERRED_API;
  if (preferredApi === "openai-completions") {
    const result = await probeOpenAICompletions(baseUrl, apiKey, model);
    if (result.ok) return { valid: true, apiPath: "openai-completions" };
    const { kind, retry } = classifyFailure(result.status, result.error);
    return {
      valid: false, apiPath: "openai-completions",
      error: result.error, failureKind: kind, retryHint: retry,
    };
  }

  const responsesResult = await probeOpenAIResponses(baseUrl, apiKey, model);
  if (responsesResult.ok) return { valid: true, apiPath: "openai-responses" };

  const completionsResult = await probeOpenAICompletions(baseUrl, apiKey, model);
  if (completionsResult.ok) return { valid: true, apiPath: "openai-completions" };

  // Classify the best error
  const bestResult = completionsResult.status != null ? completionsResult : responsesResult;
  const { kind, retry } = classifyFailure(bestResult.status, bestResult.error);
  return {
    valid: false, apiPath: "openai-completions",
    error: bestResult.error, failureKind: kind, retryHint: retry,
  };
}

export async function listOllamaModels(baseUrl: string): Promise<string[]> {
  try {
    const url = `${baseUrl.replace(/\/$/, "")}/api/tags`;
    const res = await fetch(url, { signal: AbortSignal.timeout(5_000) });
    if (!res.ok) return [];
    const data = await res.json() as any;
    return (data.models ?? []).map((m: any) => m.name as string);
  } catch {
    return [];
  }
}

export function getRecoveryMessage(result: ValidationResult): string {
  switch (result.failureKind) {
    case "transport":
      return "Check that the endpoint URL is correct and reachable. If using a local server, ensure it is running.";
    case "credential":
      return "The API key appears invalid or expired. Re-enter your credentials.";
    case "model":
      return "The requested model was not found. Choose a different model or verify it is deployed.";
    case "endpoint":
      return "The endpoint did not accept the request. Verify the URL and API compatibility.";
    default:
      return "Validation failed. You can retry, change provider, or continue and hope for the best.";
  }
}
