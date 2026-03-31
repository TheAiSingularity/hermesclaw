# HermesClaw Skills Library

Pre-built Hermes skills for common workflows. Skills are instruction files that Hermes reads and executes — they encode recurring tasks so you don't have to prompt from scratch every time.

---

## What are Hermes skills?

Skills are directories in `~/.hermes/skills/`. Each contains a `SKILL.md` file with YAML metadata and Markdown instructions that Hermes follows when you invoke the skill. Hermes also auto-creates skills from your sessions via DSPy + GEPA optimization.

Skills in this library are starting points — Hermes will refine them based on your feedback over time.

---

## Available skills

| Skill | Use case | Key tools |
|-------|----------|-----------|
| [research-digest](#research-digest) | Weekly paper digest to Telegram | web_search, web_extract, cron, telegram |
| [code-review](#code-review) | Local code review from VS Code or CLI | terminal, file, memory |
| [home-assistant](#home-assistant) | Natural language smart home control | mcp:home-assistant, cron, memory |
| [anomaly-detection](#anomaly-detection) | Daily DB anomaly reports to Slack/Telegram | mcp:postgres, cron |
| [slack-support](#slack-support) | Slack support bot with knowledge base | file, slack gateway |
| [market-alerts](#market-alerts) | Price threshold alerts to Telegram | web_extract, cron, telegram |

---

## Install

```bash
# Install one skill
./skills/install.sh research-digest

# Install multiple
./skills/install.sh code-review anomaly-detection

# Install all
./skills/install.sh --all

# List available skills
./skills/install.sh --list
```

Skills are copied to `~/.hermes/skills/` — the directory Hermes watches for skills. In Docker mode, this directory is volume-mounted so it persists across container restarts.

**Docker mode**: restart the hermesclaw container after installing:
```bash
docker compose restart hermesclaw
```

**OpenShell mode**: `~/.hermes/skills/` is mounted into the sandbox — skills are available immediately without a restart.

---

## Invoke a skill

After installing, tell Hermes to use it:

```bash
# CLI
hermes chat -q "run research-digest"
hermesclaw chat "run anomaly-detection"

# Via Telegram / Slack / Discord
"run the market-alerts skill now"
"run research-digest and send me the results"
```

You can also let Hermes auto-invoke skills — when it recognizes a task that matches a skill, it loads it automatically.

---

## Skill reference

### research-digest

**What it does**: Searches arXiv and the web for papers matching your research interests (read from MEMORY.md), synthesizes a weekly briefing, and sends it to Telegram.

**Setup**:
1. Install: `./skills/install.sh research-digest`
2. Set your research interests in memory: `hermes chat -q "I research [your topics]. Remember this."`
3. Schedule: `hermes chat -q "Every Monday 8am, run research-digest and send to Telegram"`

**Guide**: [docs/use-cases/01-researcher/](../docs/use-cases/01-researcher/)

---

### code-review

**What it does**: Reviews a file, function, or git diff for bugs, security issues, edge cases, and style — using your codebase conventions from MEMORY.md.

**Setup**:
1. Install: `./skills/install.sh code-review`
2. Orient to your codebase: `hermes chat -q "This is a [language] project using [framework]. Remember these conventions: [conventions]"`
3. Invoke: `hermes chat -q "Review /path/to/file.py"` or use VS Code ACP

**Guide**: [docs/use-cases/02-developer/](../docs/use-cases/02-developer/)

---

### home-assistant

**What it does**: Parses natural language home control commands and invokes the Home Assistant MCP server. Learns your routines and creates cron skills for them.

**Requires**: Home Assistant MCP server configured in hermes.yaml (see guide).

**Setup**:
1. Configure HA MCP in `configs/hermes.yaml`
2. Install: `./skills/install.sh home-assistant`
3. Invoke: "Turn on the living room lights" via Telegram

**Guide**: [docs/use-cases/03-home-automation/](../docs/use-cases/03-home-automation/)

---

### anomaly-detection

**What it does**: Runs SQL queries against your Postgres database, computes z-scores against a 7-day rolling baseline, flags anomalies (> 2σ), and sends a daily summary to Slack or Telegram.

**Requires**: Postgres MCP server configured in hermes.yaml.

**Includes**: `scripts/detect.py` — helper that reads query results from stdin and outputs a JSON anomaly report.

**Setup**:
1. Configure Postgres MCP in `configs/hermes.yaml`
2. Install: `./skills/install.sh anomaly-detection`
3. Configure metric queries in memory
4. Schedule: `hermes chat -q "Run anomaly-detection daily at 7am"`

**Guide**: [docs/use-cases/04-data-analyst/](../docs/use-cases/04-data-analyst/)

---

### slack-support

**What it does**: Handles incoming Slack messages. Classifies intent (FAQ / troubleshooting / escalation), answers from your knowledge base in `knowledge/`, and escalates complex cases.

**Setup**:
1. Add support docs to `knowledge/`
2. Configure Slack gateway in hermes.yaml
3. Install: `./skills/install.sh slack-support`
4. Configure escalation rules in memory

**Guide**: [docs/use-cases/05-small-business/](../docs/use-cases/05-small-business/)

---

### market-alerts

**What it does**: Monitors your watchlist for price threshold breaches via web_extract, sends immediate Telegram alerts, and generates daily pre-market briefings. Stores trade notes in MEMORY.md for strategy review.

**Includes**: `scripts/monitor.py` — helper that parses price data and computes threshold status as JSON.

**Setup**:
1. Install: `./skills/install.sh market-alerts`
2. Set watchlist and thresholds in memory
3. Schedule: `hermes chat -q "Monitor my watchlist every 15 minutes and alert me via Telegram"`

**Guide**: [docs/use-cases/07-trader/](../docs/use-cases/07-trader/)

---

## Contributing skills

If you build a skill that works well for your use case, contributions are welcome:

1. Create `skills/<your-skill-name>/SKILL.md` following the existing format
2. Test it: `./skills/install.sh your-skill-name && hermes chat -q "run your-skill-name"`
3. Open a PR — see [CONTRIBUTING.md](../CONTRIBUTING.md)

The skill format follows the [agentskills.io](https://agentskills.io) open standard.
