# Use Case 01 — Researcher / Writer

**Stack**: Docker + Telegram gateway + weekly arXiv digest cron

**What you get**: A persistent AI research assistant that remembers your ongoing projects across weeks, delivers a weekly paper digest to your phone via Telegram, and gets smarter over time as it auto-creates domain-specific skills.

---

## What this looks like in practice

- Monday 8am: Hermes sends you a Telegram message with the 5 most relevant arXiv papers from the past week, summarized in plain language
- Any time: ask "What did I find out about attention-free transformers last month?" — Hermes recalls from its memory files
- After ~20 research sessions: Hermes auto-creates a `research_synthesis` skill tuned to your research style

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Desktop | [install](https://docs.docker.com/get-docker/) |
| A GGUF model | Recommended: `Qwen3-4B-Q4_K_M.gguf` (~2.5 GB). Any 4–14B model works. |
| Telegram bot | Free. Takes 2 minutes. See step 2. |
| Telegram user ID | Needed to restrict access to yourself. See step 2. |

---

## Step-by-step setup

### Step 1 — Clone and configure

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw
cp .env.example .env
```

Download a model and place it in `models/`:
```bash
# Example — Qwen3 4B (fast, good for research summarization)
# Download from HuggingFace or your preferred GGUF source
ls models/   # confirm .gguf file is present
```

Edit `.env` and set at minimum:
```bash
MODEL_FILE=Qwen3-4B-Q4_K_M.gguf   # filename of your model in models/
```

---

### Step 2 — Create a Telegram bot

1. Open Telegram, search for `@BotFather`
2. Send `/newbot`, follow prompts, copy the **bot token**
3. Get your Telegram user ID: message `@userinfobot`, note the numeric ID

Set in `.env`:
```bash
TELEGRAM_BOT_TOKEN=1234567890:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

### Step 3 — Enable Telegram gateway in Hermes config

Copy the example config:
```bash
cp configs/hermes.yaml.example configs/hermes.yaml
```

Edit `configs/hermes.yaml` — find the `gateway:` section and enable Telegram:
```yaml
gateway:
  telegram:
    enabled: true
    # Restrict to your Telegram user ID (recommended)
    allowed_users: [YOUR_TELEGRAM_USER_ID]
```

Mount your config in `docker-compose.yml` — it already mounts `./configs:/sandbox/configs:ro`. Tell Hermes to load it by adding to the `hermesclaw` service environment:
```yaml
environment:
  HERMES_CONFIG: /sandbox/configs/hermes.yaml
```

---

### Step 4 — Start everything

```bash
docker compose up -d
```

Wait ~60 seconds for both services to be healthy:
```bash
docker compose ps   # both should show "healthy"
```

---

### Step 5 — Install the research-digest skill

From the repo root:
```bash
./skills/install.sh research-digest
```

This copies `skills/research-digest/` into `~/.hermes/skills/` on your host (which is mounted into the container).

---

### Step 6 — Tell Hermes your research areas

This personalizes the weekly digest. Send a message to your Telegram bot:

```
I'm a researcher focused on: transformer architectures, efficient attention mechanisms,
and federated learning. My current projects are: (1) efficient LLM fine-tuning survey,
(2) privacy-preserving collaborative training. Please remember these interests.
```

Hermes writes this to its `MEMORY.md` and uses it for every future digest.

---

### Step 7 — Schedule the weekly digest

In Telegram, tell Hermes:
```
Every Monday at 8am, run the research-digest skill and send me the results here.
```

Hermes creates a cron entry. You can verify with:
```bash
docker exec -it hermesclaw hermes cron list
```

---

## Verification

Send a test message to your Telegram bot:
```
Run research-digest now as a test
```

Expected: Hermes searches arXiv, finds recent papers, summarizes top 5, sends them back in Telegram within 2–3 minutes.

Check that memory persists:
```bash
docker exec hermesclaw cat /opt/hermes-data/memories/MEMORY.md
# Should show your research interests
```

Restart the stack and confirm memory survives:
```bash
docker compose down && docker compose up -d
# Then ask in Telegram: "what are my research areas?"
# Hermes should recall them from memory
```

---

## Example conversations

**Weekly digest** (auto, Monday 8am):
> Here are 5 papers from this week relevant to your interests:
> 1. **FlashAttention-4** (Stanford, 2026-03-28) — 3.2× faster than FA3 on A100. Key: fused GEMM + softmax with persistent kernels.
> 2. **FedPrune** (MIT, 2026-03-26) — Federated pruning that reduces communication 89% without accuracy loss...

**Memory-backed research**:
> You: "What did I find about attention alternatives last month?"
> Hermes: "In your session on March 3rd you noted that Mamba-2 beats transformers on sequences >16K tokens but underperforms on reasoning tasks. You flagged the SSM-Transformer hybrid paper by Li et al. as the most promising direction."

**Deep dive on demand**:
> You: "Find and summarize all papers on KV cache compression published since January"
> Hermes: [searches arXiv, returns structured summary with links]

---

## Personalisation

Edit `configs/persona.yaml.example` → `configs/persona.yaml`:
```yaml
name: "Dr. Chen"
role: "ML researcher"
expertise: ["transformer architectures", "federated learning"]
communication_style: "technical, concise, use LaTeX for math"
```

For deeper personalisation, tell Hermes directly:
```
Update your understanding of me: I prefer summaries with one-paragraph abstract + three bullet
points on key contributions. Always include paper links.
```

---

## NemoClaw comparison

| Feature | HermesClaw | NemoClaw |
|---------|:----------:|:--------:|
| Persistent memory across sessions (MEMORY.md) | ✅ | ❌ (session-only) |
| Telegram gateway | ✅ | ✅ (via OpenClaw) |
| Web search + arXiv access | ✅ | ✅ (via OpenClaw) |
| Weekly cron scheduling | ✅ | ✅ (via OpenClaw) |
| Self-improving skills (DSPy + GEPA) | ✅ | ❌ |
| Local model inference on macOS | ✅ | ❌ (DNS bug, issue #260) |
| No cloud API key required | ✅ | ❌ (cloud inference required on macOS) |
| OpenShell sandbox | Optional | ✅ |

**Where NemoClaw falls short for this use case**: NemoClaw (via OpenClaw) has Telegram, web search, and cron — so the pipeline can run. The missing piece is **persistent memory**: Hermes builds a USER.md and MEMORY.md that accumulates your research context across weeks. Without this, the weekly digest resets every session and cannot build on prior work.
