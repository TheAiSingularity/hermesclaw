# Use Case 02 — Developer (VS Code + Local Code Assistant)

**Stack**: Docker + `hermes acp` + VS Code ACP extension

**What you get**: A local AI coding assistant running inside VS Code — with full codebase context, persistent memory of your project's architecture, and zero code leaving your machine.

---

## What this looks like in practice

- Open any file in VS Code, select a function, press a hotkey → Hermes reviews it for bugs, edge cases, and style issues
- "Why does this module use a singleton?" → Hermes checks its memory of your codebase architecture and explains
- After reviewing 20+ files: Hermes auto-creates a `code_review` skill calibrated to your project's conventions
- Works entirely offline — no code is sent to any external API

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Desktop | [install](https://docs.docker.com/get-docker/) |
| VS Code | [install](https://code.visualstudio.com/) |
| A GGUF model | Recommended: `Qwen3-14B-Q4_K_M.gguf` for code (~8 GB). 7B also works. |
| Node.js 18+ | For running MCP servers |

---

## Step-by-step setup

### Step 1 — Clone and start HermesClaw

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw
cp .env.example .env
```

Download a code-capable model into `models/`. Qwen3 models are strong at code:
```bash
# Set in .env:
MODEL_FILE=Qwen3-14B-Q4_K_M.gguf
CTX_SIZE=16384   # larger context for code review
```

Start the stack:
```bash
docker compose up -d
docker compose ps   # wait until both services are "healthy"
```

---

### Step 2 — Install the VS Code ACP extension

The ACP (Agent Communication Protocol) extension connects VS Code to any ACP-compatible agent, including Hermes.

1. Open VS Code
2. Go to Extensions (`Ctrl+Shift+X` / `Cmd+Shift+X`)
3. Search for **"ACP"** or **"Agent Communication Protocol"**
4. Install the extension by i-am-bee / BeeAI

---

### Step 3 — Start the Hermes ACP server

Hermes runs as an ACP stdio server. The VS Code extension communicates with it directly.

Option A — run ACP inside the Docker container:
```bash
docker exec -it hermesclaw hermes acp
```

Option B — if Hermes is installed locally on your machine:
```bash
hermes acp
```

The ACP server starts and listens on stdio. Leave this terminal open.

---

### Step 4 — Connect VS Code to Hermes

In VS Code:
1. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`)
2. Run: `ACP: Connect to Agent`
3. Choose **stdio** mode
4. Enter the command: `docker exec -i hermesclaw hermes acp`

The ACP panel will show Hermes as connected. You'll see a chat interface in the sidebar.

---

### Step 5 — Add Git MCP server (optional but recommended)

The Git MCP server gives Hermes access to your git history for richer code review context.

Add to `configs/hermes.yaml` (create it from the example if you haven't):
```yaml
mcp:
  servers:
    git:
      command: npx
      args: ["-y", "@modelcontextprotocol/server-git", "--repository", "/workspace"]
```

Mount your project into the container by adding to the `hermesclaw` service in `docker-compose.yml`:
```yaml
volumes:
  - /path/to/your/project:/workspace:ro
```

Restart: `docker compose up -d`

---

### Step 6 — Install the code-review skill

```bash
./skills/install.sh code-review
```

This installs the skill into `~/.hermes/skills/code-review/` (mounted into the container).

---

### Step 7 — Orient Hermes to your codebase

In the ACP chat panel in VS Code:
```
This is a Python FastAPI project. We use async/await throughout, Pydantic v2 for models,
and SQLAlchemy 2.0 with async sessions. All endpoints return typed response models.
Tests use pytest-asyncio. Please remember this architecture.
```

Hermes writes this to MEMORY.md and applies it to all future code reviews.

---

## Verification

**Test code review via ACP**:
1. Open any Python/TypeScript file in VS Code
2. Select a function
3. In the ACP chat: "Review this function for bugs and edge cases"
4. Hermes should respond with a structured review within 15–30 seconds

**Test via CLI**:
```bash
docker exec -it hermesclaw hermes chat -q "Review this Python function: def divide(a, b): return a / b"
# Expected: Hermes flags the ZeroDivisionError and suggests a guard
```

**Test memory persistence**:
```bash
docker exec hermesclaw cat /opt/hermes-data/memories/MEMORY.md
# Should contain your codebase architecture notes
```

---

## Example interactions

**Inline code review**:
> You: "Review this function for edge cases"
> Hermes: "Found 2 issues: (1) No guard for empty list input — will raise IndexError on line 12. (2) The timeout is hardcoded to 30s; this should be a parameter with a sensible default. Suggested fix: [code block]"

**Architecture questions**:
> You: "Why do we use a singleton for the database connection pool?"
> Hermes: "Based on your architecture notes, the pool is a singleton because FastAPI creates one instance per worker process and SQLAlchemy's async pool is not thread-safe across processes."

**Documentation generation**:
> You: "Generate docstrings for all functions in this file that don't have them"
> Hermes: [reads file, writes docstrings, returns diffs]

**Debugging**:
> You: "I'm getting 'relation does not exist' in prod but not locally. Check the migration history."
> Hermes: [reads git log, checks migration files, identifies the missing migration]

---

## NemoClaw comparison

| Feature | HermesClaw | NemoClaw |
|---------|:----------:|:--------:|
| VS Code ACP integration | ✅ | ⚠️ (OpenClaw-native, not ACP standard) |
| Persistent codebase memory (MEMORY.md) | ✅ | ❌ (session-only) |
| MCP server support | ✅ | ❌ (unconfirmed) |
| Local model (code never leaves machine) | ✅ | ❌ on macOS (cloud API required) |
| Self-improving code review skill | ✅ | ❌ |
| OpenShell sandbox | Optional | ✅ |

**Where NemoClaw falls short for this use case**: ACP is an open standard — VS Code, Zed, and JetBrains integrate with it natively. OpenClaw has its own IDE integration, which may not be compatible with these editors. More critically, on macOS NemoClaw routes inference to cloud APIs — your proprietary code is sent externally on every review request.
