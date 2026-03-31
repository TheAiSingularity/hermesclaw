# Use Case 03 — Home Automation (Home Assistant + Telegram)

**Stack**: Docker + Home Assistant MCP + Telegram gateway

**What you get**: Control your smart home from Telegram using natural language. Hermes learns your routines over time and auto-creates cron skills for them. All inference stays on your home server — no cloud dependency.

---

## What this looks like in practice

- "Turn off all lights and set thermostat to 68" → done via Telegram
- "When I say goodnight, run the sleep routine" → Hermes creates a cron skill
- Voice notes auto-transcribed before reaching the agent
- Hermes remembers your preferences: "always leave the porch light on after 9pm"
- Works offline — your phone reaches your home server via Tailscale or local network

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Desktop | On your home server (Linux/macOS/Windows) |
| A GGUF model | Recommended: `Qwen3-4B-Q4_K_M.gguf` (~2.5 GB). Runs well on 16GB RAM. |
| Home Assistant | Running on your network. [Install HA](https://www.home-assistant.io/installation/) |
| HA Long-Lived Access Token | Generated in HA → Profile → Long-Lived Access Tokens |
| Telegram bot | See [Step 2](#step-2--create-a-telegram-bot) |
| Node.js 18+ | For the Home Assistant MCP server |

---

## Architecture

```
Your phone (Telegram)
    │
    ▼
Hermes Agent (Docker container on home server)
    │  ← reads: ~/.hermes/memories/ (your preferences, routines)
    │  ← skill: home-assistant-control
    │
    ▼
Home Assistant MCP server
    │
    ▼
Home Assistant (your local HA instance)
    │
    ├── lights
    ├── thermostat
    ├── locks
    └── ...
```

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
MODEL_FILE=Qwen3-4B-Q4_K_M.gguf
TELEGRAM_BOT_TOKEN=                 # filled in step 2
HA_TOKEN=                           # filled in step 3
HA_URL=http://homeassistant.local:8123   # or your HA IP
```

---

### Step 2 — Create a Telegram bot

1. Message `@BotFather` in Telegram
2. Send `/newbot`, follow prompts
3. Copy the bot token into `.env` as `TELEGRAM_BOT_TOKEN`
4. Get your user ID from `@userinfobot`

---

### Step 3 — Get a Home Assistant token

1. In Home Assistant, go to your **Profile** (bottom-left avatar)
2. Scroll to **Long-Lived Access Tokens**
3. Click **Create Token**, name it "hermesclaw", copy the token
4. Set in `.env`: `HA_TOKEN=<your token>`

---

### Step 4 — Add the Home Assistant MCP server to Hermes config

Copy the Hermes config:
```bash
cp configs/hermes.yaml.example configs/hermes.yaml
```

Edit `configs/hermes.yaml`:

```yaml
gateway:
  telegram:
    enabled: true
    allowed_users: [YOUR_TELEGRAM_USER_ID]

mcp:
  servers:
    home-assistant:
      url: "http://homeassistant.local:8123/mcp"
      headers:
        Authorization: "Bearer ${HA_TOKEN}"
      timeout: 30
```

> **Note**: This uses the official Home Assistant MCP Server integration (built into HA 2024.11+). Enable it in HA under **Settings → Devices & Services → Add Integration → Model Context Protocol Server**. The MCP endpoint is available at `http://your-ha-ip:8123/mcp`.

Add `HERMES_CONFIG: /sandbox/configs/hermes.yaml` to the `hermesclaw` environment section in `docker-compose.yml`.

---

### Step 5 — Set the gateway policy

```bash
# Gateway policy allows: inference + Telegram (no web search or GitHub)
hermesclaw policy-set gateway
# Or if running Docker-only mode, this is handled by the config above
```

---

### Step 6 — Start everything

```bash
docker compose up -d
docker compose ps   # wait for "healthy"
```

---

### Step 7 — Install the home-assistant skill

```bash
./skills/install.sh home-assistant
```

---

### Step 8 — Test the connection

```bash
# Verify Home Assistant MCP is reachable
docker exec -it hermesclaw hermes chat -q "List all available Home Assistant entities"
# Expected: Hermes returns a list of lights, sensors, switches, etc. from your HA instance
```

---

## Verification

Send via Telegram to your bot:
```
Turn on the kitchen lights
```

Expected: Hermes invokes the HA MCP, calls the `light.turn_on` service, confirms in Telegram.

Test routine creation:
```
Every weekday at 7am, turn on the coffee maker and set the thermostat to 72
```

Expected: Hermes creates a cron entry and confirms. Verify:
```bash
docker exec hermesclaw hermes cron list
```

Test voice: Record a voice note saying "Turn off all lights" and send it to the bot. Hermes auto-transcribes and executes.

---

## Example conversations

**Direct control**:
> You: "Lock the front door and turn off all lights except the porch"
> Hermes: "Done. Front door locked. Turned off: living room, kitchen, bedroom, office. Porch light left on (matching your saved preference)."

**Routine creation**:
> You: "Create a sleep routine: turn off all lights, lock all doors, set thermostat to 66, mute the TV"
> Hermes: "Sleep routine created. Say 'goodnight' any time to trigger it."

**Status check**:
> You: "Is anything left on?"
> Hermes: "Living room TV is on. Office lights are on. Front door is unlocked."

**Learning routines**:
> [After you repeatedly ask for similar things...]
> Hermes: "I noticed you turn on the coffee maker every weekday at 7:05am. Want me to automate this?"

---

## Remote access from your phone

To reach your home server from outside your home network:

**Option A — Tailscale** (recommended, free):
```bash
# Install Tailscale on your home server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Your server gets a stable IP like 100.x.x.x accessible from your phone
```

**Option B — Telegram webhook mode** (requires public URL):
```yaml
gateway:
  telegram:
    enabled: true
    webhook_mode: true
    webhook_url: https://yourdomain.com/webhook   # via Cloudflare Tunnel or similar
```

---

## NemoClaw comparison

| Feature | HermesClaw | NemoClaw |
|---------|:----------:|:--------:|
| Home Assistant MCP | ✅ | ❌ (MCP support unconfirmed) |
| Telegram gateway | ✅ | ✅ (via OpenClaw) |
| Persistent routines (MEMORY.md) | ✅ | ❌ (session-only) |
| Voice note transcription | ✅ | ✅ (via OpenClaw) |
| Local inference (commands stay on device) | ✅ | ❌ on macOS (cloud API required) |
| OpenShell sandbox | Optional | ✅ |

**Where NemoClaw falls short for this use case**: NemoClaw (via OpenClaw) supports Telegram and voice — so basic natural language commands to your home are possible. The gap is **MCP support**: HermesClaw connects directly to your Home Assistant instance via MCP, giving it full read/write access to every device. NemoClaw has no confirmed MCP integration, so HA control would require a custom workaround. Also: learned routines require persistent memory across sessions, which OpenClaw does not provide.
