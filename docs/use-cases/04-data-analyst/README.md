# Use Case 04 — Data Analyst (Postgres MCP + Anomaly Detection)

**Stack**: Docker + Postgres MCP + daily anomaly detection cron

**What you get**: A private data analysis assistant that queries your production databases directly, detects anomalies automatically, and sends alerts to Slack or Telegram — with all data staying within your infrastructure.

---

## What this looks like in practice

- Every morning at 7am: Hermes queries your Postgres database, compares today's revenue/signups/retention against the 7-day rolling average, and sends a summary to Slack
- Any anomalies (> 2σ from mean): an immediate alert with the affected metric, magnitude, and likely cause
- On demand: "What's the week-over-week change in activation rate for users who signed up via referral?"
- After 2 months: Hermes auto-creates an `AnomalyDetector` skill tuned to your specific metrics

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Desktop | [install](https://docs.docker.com/get-docker/) |
| A GGUF model | Recommended: `Qwen3-14B-Q4_K_M.gguf` for complex SQL generation |
| PostgreSQL | Your existing DB, accessible from the Docker network |
| Node.js 18+ | For MCP server |
| Slack or Telegram | For alert delivery |

---

## Step-by-step setup

### Step 1 — Clone and configure

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw
cp .env.example .env
```

Edit `.env`:
```bash
MODEL_FILE=Qwen3-14B-Q4_K_M.gguf

# Your Postgres connection string
DATABASE_URL=postgresql://user:password@your-db-host:5432/your_database

# Alert delivery (pick one or both)
TELEGRAM_BOT_TOKEN=           # optional
SLACK_BOT_TOKEN=              # optional
```

---

### Step 2 — Add the Postgres MCP server

Copy the Hermes config:
```bash
cp configs/hermes.yaml.example configs/hermes.yaml
```

Edit `configs/hermes.yaml`, add the MCP section:
```yaml
mcp:
  servers:
    postgres:
      command: npx
      args:
        - "-y"
        - "@modelcontextprotocol/server-postgres"
        - "${DATABASE_URL}"
      timeout: 60
```

> **Note**: `@modelcontextprotocol/server-postgres` is now in the MCP servers archive but remains functional. Active community alternatives: `HenkDz/postgresql-mcp-server` (feature-rich, maintained) and the pgEdge Postgres MCP Server. Swap the package name in the `args` line to use an alternative.

Enable your alert channel in the `gateway:` section:
```yaml
gateway:
  slack:
    enabled: true     # if using Slack
  telegram:
    enabled: true     # if using Telegram
    allowed_users: [YOUR_TELEGRAM_USER_ID]
```

Add to the `hermesclaw` service environment in `docker-compose.yml`:
```yaml
environment:
  HERMES_CONFIG: /sandbox/configs/hermes.yaml
  DATABASE_URL: "${DATABASE_URL}"
```

---

### Step 3 — Start everything

```bash
docker compose up -d
docker compose ps   # wait for "healthy"
```

Verify database connection:
```bash
docker exec -it hermesclaw hermes chat -q "List the tables in the database"
# Expected: Hermes returns a table list via the Postgres MCP
```

---

### Step 4 — Install the anomaly-detection skill

```bash
./skills/install.sh anomaly-detection
```

This installs the skill plus the `detect.py` helper script into `~/.hermes/skills/anomaly-detection/`.

---

### Step 5 — Configure your key metrics

Tell Hermes which metrics to monitor (it writes this to memory):
```bash
docker exec -it hermesclaw hermes chat -q "
I want to monitor these daily metrics:
- Daily active users: SELECT COUNT(DISTINCT user_id) FROM events WHERE created_at >= CURRENT_DATE
- Daily revenue: SELECT SUM(amount) FROM payments WHERE created_at >= CURRENT_DATE
- New signups: SELECT COUNT(*) FROM users WHERE created_at >= CURRENT_DATE
- Activation rate: SELECT COUNT(*) FILTER (WHERE activated) * 100.0 / COUNT(*) FROM users WHERE created_at >= CURRENT_DATE - 7

Please remember these queries and use them for daily anomaly detection.
"
```

---

### Step 6 — Schedule daily anomaly detection

```bash
docker exec -it hermesclaw hermes chat -q "
Every day at 7am, run anomaly-detection on my key metrics and send the results to Slack.
If any metric deviates more than 2 standard deviations from the 7-day average, also send an immediate alert.
"
```

Verify the cron was created:
```bash
docker exec hermesclaw hermes cron list
```

---

## Verification

**Test manual analysis**:
```bash
docker exec -it hermesclaw hermes chat -q "
Summarize yesterday's key metrics vs the past 7-day average.
Highlight any unusual changes.
"
```

**Test anomaly detection**:
```bash
docker exec -it hermesclaw hermes chat -q "Run anomaly-detection now"
# Expected: Hermes runs queries, computes z-scores, reports any anomalies
```

**Test ad-hoc query**:
```bash
docker exec -it hermesclaw hermes chat -q "
What was the week-over-week change in revenue by acquisition channel last week?
"
# Expected: Hermes writes and runs the SQL, returns a structured summary
```

---

## Example outputs

**Daily summary (no anomalies)**:
> Daily metrics — 2026-03-31
> DAU: 8,432 (↑3.2% vs 7-day avg of 8,168) — normal
> Revenue: $24,150 (↓1.1% vs 7-day avg of $24,420) — normal
> New signups: 312 (↑0.8%) — normal
> Activation rate: 67.3% (vs avg 68.1%) — normal

**Anomaly alert**:
> ALERT — 2026-03-31 07:03
> Revenue anomaly detected: $15,200 (−38% vs 7-day avg of $24,420, z-score: −2.8)
> Possible causes: payment processor issue, pricing change, regional outage
> Check: SELECT * FROM payment_failures WHERE created_at >= CURRENT_DATE

**Ad-hoc query**:
> Week-over-week revenue by channel (W12 vs W11):
> | Channel | W12 | W11 | Change |
> |---------|-----|-----|--------|
> | Organic | $45,200 | $41,800 | +8.1% |
> | Paid | $31,500 | $35,200 | −10.5% |
> | Referral | $12,100 | $9,800 | +23.5% |

---

## Security notes

- The Postgres MCP server connects to your database from within the Docker network
- Set `DATABASE_URL` to a **read-only** database user to prevent write operations:
  ```sql
  CREATE ROLE hermes_reader WITH LOGIN PASSWORD 'your_password';
  GRANT CONNECT ON DATABASE your_database TO hermes_reader;
  GRANT USAGE ON SCHEMA public TO hermes_reader;
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO hermes_reader;
  ```
- If using OpenShell mode, the network policy limits the container to your DB host only — no other outbound connections

---

## NemoClaw comparison

| Feature | HermesClaw | NemoClaw |
|---------|:----------:|:--------:|
| Postgres MCP | ✅ | ❌ (MCP support unconfirmed) |
| Persistent metric memory (MEMORY.md) | ✅ | ❌ (session-only) |
| Slack / Telegram alerts | ✅ | ✅ (via OpenClaw) |
| Scheduled anomaly detection (cron) | ✅ | ✅ (via OpenClaw) |
| Self-improving detection skill | ✅ | ❌ |
| Local inference (query results stay internal) | ✅ | ❌ on macOS (cloud API required) |
| OpenShell sandbox | Optional | ✅ |

**Where NemoClaw falls short for this use case**: NemoClaw (via OpenClaw) has Slack, Telegram, and cron — the alerting pipeline can work. The critical gap is **Postgres MCP**: HermesClaw connects directly to your database and runs arbitrary SQL queries. Without MCP, NemoClaw would need a custom integration layer. Additionally, sending your production metric data to an external API (OpenAI/Anthropic) on every analysis run raises data residency concerns that may block adoption in regulated industries.
