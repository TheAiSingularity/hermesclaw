# Use Case 07 — Trader / Quant (Low-Latency Local Inference + Telegram Alerts)

**Stack**: Docker + Qwen3-7B (quantized, fast) + Telegram alerts + market monitoring cron

**What you get**: A persistent trading assistant with sub-second local inference, real-time market alerts to Telegram, strategy memory that learns from past performance, and a sandbox for safe backtesting. No cloud API latency — no $0.01 per inference cost at scale.

---

## What this looks like in practice

- Price drops below your threshold: Telegram alert arrives in < 2 seconds (local inference, no API round-trip)
- "What was the outcome of my NVDA thesis from last week?" → Hermes recalls from strategy memory
- Daily market open: summary of your watchlist vs previous close, macro news summary, and pending position notes
- After 3 months: Hermes auto-creates a `MarketAlert` skill calibrated to your trading style
- Backtesting: run simulated strategies in the sandbox — OpenShell ensures the container can't accidentally touch live accounts

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Desktop | [install](https://docs.docker.com/get-docker/) |
| Qwen3-7B-Q4_K_M.gguf | ~4 GB. Fast inference (key for latency). Download from HuggingFace. |
| Telegram bot | For alerts. See [Step 2](#step-2--create-a-telegram-bot). |
| 16 GB RAM | Qwen3-7B runs comfortably at 16GB. Use 4B if you have 8GB. |

**Optional for GPU acceleration** (reduces inference to ~50ms):
- NVIDIA GPU with 8+ GB VRAM + NVIDIA Container Toolkit
- `docker compose --profile gpu up` instead of `docker compose up`

---

## Latency comparison

| Setup | Inference latency (7B model, ~200 token response) |
|-------|---------------------------------------------------|
| Cloud API (OpenAI, Anthropic) | 200–500ms + network round-trip |
| HermesClaw + Qwen3-7B CPU | 800ms–2s (depends on hardware) |
| HermesClaw + Qwen3-7B GPU | 50–150ms |

For alert generation and market monitoring, even the CPU numbers are faster than cloud API latency when you factor in network overhead.

---

## Step-by-step setup

### Step 1 — Clone and configure

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw
cp .env.example .env
```

Download Qwen3-7B-Q4 into `models/`:
```bash
# Download from HuggingFace (example URL pattern — use your preferred source)
# Filename: Qwen3-7B-Q4_K_M.gguf (~4 GB)
ls models/
```

Edit `.env`:
```bash
MODEL_FILE=Qwen3-7B-Q4_K_M.gguf
CTX_SIZE=32768              # must be >= 32768 (Hermes system prompt is ~11k tokens)
TELEGRAM_BOT_TOKEN=         # filled in step 2
```

---

### Step 2 — Create a Telegram bot

1. Message `@BotFather` in Telegram
2. Send `/newbot`, follow prompts
3. Copy bot token → set `TELEGRAM_BOT_TOKEN` in `.env`
4. Get your user ID from `@userinfobot`

---

### Step 3 — Configure Hermes

```bash
cp configs/hermes.yaml.example configs/hermes.yaml
```

Edit `configs/hermes.yaml`:
```yaml
model:
  default: local
  reasoning: low      # lowest reasoning overhead for faster responses

gateway:
  telegram:
    enabled: true
    allowed_users: [YOUR_TELEGRAM_USER_ID]

tools:
  telegram:
    enabled: [web_search, web_extract, memory, skills, cron]
    # Restrict to read-only tools for safety in automated mode
```

Add to `docker-compose.yml` hermesclaw environment:
```yaml
environment:
  HERMES_CONFIG: /sandbox/configs/hermes.yaml
```

---

### Step 4 — Start the stack

CPU mode (default):
```bash
docker compose up -d
```

GPU mode (if you have NVIDIA GPU):
```bash
docker compose --profile gpu up -d
```

Verify inference speed:
```bash
time docker exec hermesclaw hermes chat -q "What is 2+2?"
# Real time should be < 2s on CPU, < 500ms on GPU
```

---

### Step 5 — Install the market-alerts skill

```bash
./skills/install.sh market-alerts
```

---

### Step 6 — Set your watchlist and thresholds

Tell Hermes your trading parameters (stored in MEMORY.md):
```
In Telegram:
"My watchlist: NVDA, TSLA, BTC-USD, ETH-USD, SPY
Alert thresholds:
- NVDA: alert if > $950 or < $820
- TSLA: alert if > $280 or < $220
- BTC: alert if > $95,000 or < $78,000
- ETH: alert if > $3,800 or < $2,900

Daily briefing: every weekday at 9:25am (5 mins before market open)
Real-time monitoring: every 15 minutes during market hours (9:30am–4pm ET)

Please remember this watchlist and alert configuration."
```

---

### Step 7 — Schedule market monitoring

In Telegram:
```
Schedule: every 15 minutes from 9:30am to 4pm ET Monday through Friday,
run market-alerts on my watchlist and send me alerts for any threshold breaches.

Also: every weekday at 9:25am, send me a pre-market summary of my watchlist
vs yesterday's close, plus any overnight macro news.
```

Verify:
```bash
docker exec hermesclaw hermes cron list
```

---

## Verification

**Test alert generation**:
```bash
docker exec -it hermesclaw hermes chat -q "
Check current prices for NVDA and TSLA and compare against my alert thresholds.
Alert me if any threshold is breached.
"
```

**Test pre-market briefing**:
```bash
docker exec -it hermesclaw hermes chat -q "Run the pre-market summary for my watchlist"
```

**Test latency** (critical for trading use cases):
```bash
# Measure end-to-end alert generation time
time docker exec hermesclaw hermes chat -q "Is NVDA above 950?"
```

**Test strategy memory**:
```bash
docker exec -it hermesclaw hermes chat -q "
I just closed my NVDA long position at 940, entry was 870.
Entry thesis: Jensen keynote + blackwell cycle.
Close reason: hitting resistance at 200-day MA.
Please record this trade."
```

Then later:
```bash
docker exec -it hermesclaw hermes chat -q "What was my NVDA trade thesis and how did it perform?"
```

---

## Example outputs

**Threshold alert (via Telegram)**:
> ALERT — NVDA price breach
> Current: $823.50 (below your $820 threshold: actually above minimum, retesting support)
> Checking: 14-day RSI = 38 (approaching oversold), volume 1.2x avg
> Note from your memory: last time NVDA tested this level (Feb 12) it bounced +8% in 3 days

**Pre-market briefing**:
> Pre-market summary — 2026-03-31 (9:25am ET)
> NVDA: $847 (+1.2% pre-mkt) — earnings in 3 days, options IV elevated
> TSLA: $231 (−0.4% pre-mkt) — delivery numbers due Thursday
> BTC: $87,200 (+2.1% overnight) — Fed minutes tonight may add volatility
> SPY: $523 (flat) — today's catalyst: PCE inflation data at 8:30am
> Your open positions from memory: TSLA long (entry $225, target $265)

**Strategy memory retrieval**:
> Your NVDA trades (from memory):
> 1. Long entry $870 → close $940 (+8.0%) — Jensen keynote + Blackwell thesis ✅
> 2. Short entry $960 → stopped $985 (−2.6%) — resistance play failed ❌
> Net: +5.4% across 2 trades. Win rate: 50%. Avg winner: 8.0%, avg loser: 2.6%.

---

## Safety notes for live trading

HermesClaw is a monitoring and analysis tool. For any live order execution:

1. **Never give the agent credentials to your brokerage** — use it for analysis and alerts only
2. For dry-run strategies, use OpenShell mode (`hermesclaw start --policy strict`) — the sandbox prevents network access to live APIs
3. All position sizing and execution decisions should remain with the human trader

---

## NemoClaw comparison

| Feature | HermesClaw | NemoClaw |
|---------|:----------:|:--------:|
| Local inference (low latency) | ✅ | ❌ on macOS (DNS bug, issue #260) |
| Persistent strategy memory (MEMORY.md) | ✅ | ❌ (session-only) |
| Telegram price alerts | ✅ | ✅ (via OpenClaw) |
| Scheduled market monitoring (cron) | ✅ | ✅ (via OpenClaw) |
| Self-improving strategy skill | ✅ | ❌ |
| Safe backtesting sandbox | ✅ | ✅ |

**The decisive factor**: NemoClaw (via OpenClaw) has Telegram alerts and cron monitoring — so both stacks can send alerts. The difference is **latency and cost**. HermesClaw with a local Qwen-7B responds in ~800ms on CPU, ~50–150ms on GPU, with zero API cost per alert. NemoClaw on macOS routes to OpenAI/Anthropic, adding 200–500ms network round-trip plus ~$0.001–0.01 per alert — at 96 alerts/day (every 15 min) that's $35–350/month in inference costs. For a persistent strategy memory that learns from your trade outcomes over months, Hermes is the only option.
