# Use Case 05 — Small Business (Slack Support Bot)

**Stack**: Docker + gateway policy + Slack bot

**What you get**: A Slack bot that handles 60–80% of routine customer/internal support inquiries automatically, escalates complex cases to a human, and learns from your knowledge base. All inference runs locally — no OpenAI costs per query.

---

## What this looks like in practice

- Customer messages your Slack bot: "What's your refund policy?" → Hermes answers from knowledge base instantly
- "I can't log in" → Hermes checks the troubleshooting guide and replies with steps
- "I want to cancel" → Hermes recognizes this as a churn risk, escalates to your support channel
- After 3 months: Hermes auto-creates an FAQ skill from the patterns it has seen
- At scale: handle hundreds of inquiries per day with local inference, zero per-query cost

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Desktop | [install](https://docs.docker.com/get-docker/) |
| A GGUF model | Recommended: `Qwen3-7B-Q4_K_M.gguf` (fast, 4 GB). Good balance for support tasks. |
| Slack workspace | With permission to create apps |
| Knowledge base | Your FAQ, docs, or support handbook as Markdown/text files |

---

## Step-by-step setup

### Step 1 — Clone and configure

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw
cp .env.example .env
```

Set in `.env`:
```bash
MODEL_FILE=Qwen3-7B-Q4_K_M.gguf
SLACK_BOT_TOKEN=        # filled in step 2
```

---

### Step 2 — Create a Slack app

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and click **Create New App → From Scratch**
2. Name it (e.g. "HermesSupport"), select your workspace
3. Under **OAuth & Permissions**, add these **Bot Token Scopes**:
   - `chat:write` — send messages
   - `channels:read` — read channel list
   - `im:history` — read DMs
   - `im:read` — access DMs
   - `im:write` — reply in DMs
   - `app_mentions:read` — respond to @mentions
4. Click **Install to Workspace**, copy the **Bot User OAuth Token**
5. Set in `.env`: `SLACK_BOT_TOKEN=xoxb-...`

Enable **Event Subscriptions** in the Slack app:
- Subscribe to bot events: `message.im`, `app_mention`
- Request URL: `https://your-server/hermes/slack` (or use socket mode for local testing)

For local testing without a public URL, use **Socket Mode**:
1. Under **Basic Information → App-Level Tokens**, create a token with `connections:write` scope
2. Set: `SLACK_APP_TOKEN=xapp-...` in `.env`

---

### Step 3 — Add your knowledge base

Put your support documents into `knowledge/`:
```bash
# Example structure
knowledge/
├── faq.md                  # Top 50 frequently asked questions
├── refund-policy.md        # Refund and cancellation policy
├── troubleshooting.md      # Common issues and fixes
├── pricing.md              # Plan details and pricing
└── escalation-triggers.md  # Cases that must go to human support
```

These files are mounted read-only into the container at `/sandbox/knowledge/`.

---

### Step 4 — Configure Hermes

```bash
cp configs/hermes.yaml.example configs/hermes.yaml
```

Edit `configs/hermes.yaml`:
```yaml
gateway:
  slack:
    enabled: true
    # Restrict to specific channels or allow all DMs
    # allowed_channels: ["C0XXXXXX"]

tools:
  slack:
    enabled: [file, memory, skills]   # limit tools available via Slack gateway
```

Add to `docker-compose.yml` hermesclaw environment:
```yaml
environment:
  HERMES_CONFIG: /sandbox/configs/hermes.yaml
  SLACK_BOT_TOKEN: "${SLACK_BOT_TOKEN}"
  SLACK_APP_TOKEN: "${SLACK_APP_TOKEN}"
```

---

### Step 5 — Set gateway policy

HermesClaw's policy controls what the agent can access. For a support bot, use `gateway`:
```bash
hermesclaw policy-set gateway
# Allows: inference.local + Slack API
# Blocks: web search, GitHub, other outbound connections
```

---

### Step 6 — Start and install the skill

```bash
docker compose up -d
./skills/install.sh slack-support
```

---

### Step 7 — Configure escalation

Tell Hermes your escalation rules:
```bash
docker exec -it hermesclaw hermes chat -q "
Your escalation policy:
- Always escalate: cancellation requests, billing disputes > $100, security issues, legal questions
- Escalation means: send a message to #support-escalations channel tagging @support-team
- For everything else: answer from /sandbox/knowledge/ documents
- If you don't know the answer, say so and offer to escalate
Please remember this policy.
"
```

---

## Verification

DM your bot in Slack:
```
What is your refund policy?
```
Expected: Hermes reads `knowledge/refund-policy.md` and answers.

```
I want to cancel my subscription
```
Expected: Hermes recognizes this as an escalation trigger, messages `#support-escalations`.

```
I can't log into my account
```
Expected: Hermes reads `knowledge/troubleshooting.md` and provides login troubleshooting steps.

Check logs:
```bash
docker compose logs hermesclaw --tail=50
```

---

## Example interactions

**FAQ**:
> User: "Do you have a free trial?"
> Hermes: "Yes! All plans include a 14-day free trial, no credit card required. After the trial, you can choose from our Starter ($29/mo), Pro ($79/mo), or Enterprise (custom) plans. Would you like to start a trial?"

**Troubleshooting**:
> User: "The export button isn't working"
> Hermes: "Let's try a few things: 1) Check you're using Chrome or Firefox (Safari has a known issue with exports). 2) Clear your cache and reload. 3) Check if you're on a plan that includes exports — the Starter plan is view-only. If none of these work, I'll escalate to the team."

**Escalation**:
> User: "I was charged twice last month"
> Hermes: "I'm sorry about that — a duplicate charge needs to be handled by our billing team directly. I've alerted @support-team in #support-escalations. Someone will reach out within 2 hours. For urgent issues, you can also email billing@yourcompany.com."

---

## Scaling notes

- **Context per conversation**: Hermes loads the relevant knowledge files for each session. Keep individual files under 10,000 tokens for best performance.
- **Concurrent users**: The single Hermes instance handles one Slack conversation at a time. For high volume (>50 concurrent sessions), run multiple HermesClaw instances behind a load balancer.
- **Cost**: Local inference with Qwen3-7B at 8192 context handles ~200 support tickets/day on a standard $50/month server (8 vCPU, 16GB RAM).

---

## NemoClaw comparison

| Feature | HermesClaw | NemoClaw |
|---------|:----------:|:--------:|
| Slack gateway | ✅ | ✅ (via OpenClaw) |
| Knowledge base from local files | ✅ | ⚠️ (unclear file access in sandbox) |
| Persistent escalation rules (MEMORY.md) | ✅ | ❌ (session-only) |
| Self-improving FAQ skill | ✅ | ❌ |
| Local inference (no per-query cost) | ✅ | ❌ on macOS (cloud API = cost per message) |
| OpenShell sandbox | Optional | ✅ |

**This use case works on both stacks** — NemoClaw (via OpenClaw) has native Slack support. The differences that matter at scale: (1) **Cost** — HermesClaw uses local llama.cpp, so 500 support tickets/day costs $0 in inference. NemoClaw on macOS routes to OpenAI/Anthropic, adding ~$0.01–0.05 per ticket. (2) **Memory** — Hermes learns your escalation patterns over time and auto-improves its responses. OpenClaw does not persist this learning between sessions.
