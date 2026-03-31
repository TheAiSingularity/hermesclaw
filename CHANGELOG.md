# Changelog

All notable changes to HermesClaw are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

*Changes staged for the next release go here.*

---

## [0.4.0] — Unreleased

### Added
- **`docs/use-cases/`** — Seven end-to-end deployment guides, one per persona:
  - `01-researcher/` — Docker + Telegram gateway + weekly arXiv digest cron
  - `02-developer/` — Docker + VS Code ACP integration + Git MCP
  - `03-home-automation/` — Docker + Home Assistant MCP + Telegram bot
  - `04-data-analyst/` — Docker + Postgres MCP + daily anomaly detection
  - `05-small-business/` — Docker + gateway policy + Slack support bot
  - `06-privacy-regulated/` — OpenShell sandbox + strict policy (HIPAA/legal/compliance)
  - `07-trader/` — Docker + Qwen-7B + Telegram market alerts
  - `README.md` — Index with quick-picker table + NemoClaw compatibility matrix across all 7 use cases
- **`skills/`** — Pre-built Hermes skills library (native SKILL.md format, installable in one command):
  - `research-digest/` — Weekly arXiv + web paper digest to Telegram
  - `code-review/` — Local code review using project conventions from memory
  - `home-assistant/` — Natural language smart home control via HA MCP
  - `anomaly-detection/` — Daily Postgres metric monitoring; flags > 2σ deviations
  - `slack-support/` — Slack support bot with knowledge base and escalation routing
  - `market-alerts/` — Watchlist threshold monitoring with Telegram alerts
- **`skills/install.sh`** — Interactive installer; copies skills to `~/.hermes/skills/`
- **`skills/anomaly-detection/scripts/detect.py`** — Z-score anomaly computation helper (stdlib only)
- **`skills/market-alerts/scripts/monitor.py`** — Price threshold comparison helper (stdlib only)
- **`README.md`** — Added "Use Cases" and "Skills Library" sections with install commands

### Changed (v0.4.0)
- **NemoClaw comparison tables corrected** across all 7 use-case guides and README:
  - Provider support: NemoClaw supports OpenAI, Anthropic, Gemini, NVIDIA NIM (not Nemotron-only)
  - Tool count: OpenClaw (the agent NemoClaw wraps) has 25+ tools and messaging channels (not ~10)
  - Telegram/Slack/Discord: NemoClaw/OpenClaw has native gateway support — corrected from "❌" to "✅"
  - macOS local inference: NemoClaw has a confirmed DNS bug (issue #260) breaking local models on macOS — added as explicit caveat
  - HermesClaw advantages clarified: persistent MEMORY.md/USER.md, self-improving skills (DSPy+GEPA), MCP server support, local inference on macOS

### Added (Phase 1 — sequential comparison test infrastructure)
- **`scripts/test-setup.sh`** — Environment verification: Docker check, model file copy, HermesClaw build/start, NemoClaw CLI check, port conflict detection, `docs/test-results-uc.md` template creation
- **`scripts/test-uc-01.sh`** — Researcher use case test: memory write/recall, Telegram (manual), cron creation, research-digest skill — both HermesClaw and NemoClaw
- **`scripts/test-uc-02.sh`** — Developer use case test: code review (SQL injection + division-by-zero detection), ACP server startup, VS Code connection (manual), code-review skill
- **`scripts/test-uc-03.sh`** — Home automation test: HA MCP connection, natural language command, routine creation — gracefully skips if no HA instance reachable
- **`scripts/test-uc-04.sh`** — Data analyst test: spins up Docker Postgres, seeds anomaly data, tests Postgres MCP, SQL queries, anomaly-detection skill, detect.py z-scores
- **`scripts/test-uc-05.sh`** — Small business test: FAQ responses, escalation trigger, knowledge base loading, slack-support skill, Slack bot (manual)
- **`scripts/test-uc-06.sh`** — Privacy-regulated test: document analysis, local inference confirmation, outbound blocking (Linux/OpenShell only), NemoClaw cloud routing documented as HIPAA-disqualifying
- **`scripts/test-uc-07.sh`** — Trader test: watchlist memory, threshold checks, market-alerts skill, monitor.py, Telegram alerts (manual), **inference latency measurement** (3-run average, HermesClaw vs NemoClaw cloud)
- All test scripts write results to `docs/test-results-uc.md` (created by test-setup.sh)

---

## [0.3.0] — Unreleased

### Fixed
- **OpenShell policy YAML schema** — corrected all 5 policy files to match the authoritative OpenShell v1 schema:
  - `process.run_as_user/run_as_group` → `process.user/group`
  - `landlock.compatibility: best_effort` → `landlock.enabled: true`
  - Endpoint format: replaced `enforcement`/`access` fields with `protocol`/`tls`
  - REST rules: renamed `rules:` to `rest:`, added `access_level:` field per endpoint
  - `binaries:` list items changed from `{path: "..."}` objects to bare glob strings
- **`scripts/setup.sh`** — removed `openshell policy apply` (not a valid OpenShell CLI command); policies are passed by file path at sandbox creation time via `--policy` flag
- **`scripts/status.sh`** — added missing `set -euo pipefail`
- **`scripts/hermesclaw`** — version bumped to `0.2.0` (was `0.1.0` despite being the v0.2.0 release)

### Changed
- **NemoClaw comparison** — corrected inference provider comparison: NemoClaw supports Nemotron via NVIDIA API only; does not support local llama.cpp, OpenAI, Anthropic, Ollama, or vLLM backends
- **Branding** — removed "world's first" / "nobody had done it" language from README, CONTRIBUTING.md, CHANGELOG, and profile YAML; replaced with neutral description of this being a community implementation built on NVIDIA OpenShell and NousResearch Hermes Agent

### Added
- **Use cases** — two documented use cases in README demonstrating where Hermes capabilities add practical value beyond NemoClaw: persistent research assistant and local AI messaging gateway

---

## [0.2.0] — 2026-03-31

### Added
- **`hermesclaw` CLI** — full sandbox management CLI with `start`, `stop`, `status`, `connect`, `logs`, `policy-list`, `policy-set`, `doctor`, `chat`, `onboard`, `version`, `uninstall` commands
- **Policy presets** — `policy-strict.yaml`, `policy-gateway.yaml`, `policy-permissive.yaml` for tiered security postures
- **`scripts/doctor.sh`** — end-to-end diagnostic report table; checks Docker, OpenShell, llama.cpp, Hermes, image, config, model files, policy files, sandbox status
- **`scripts/test.sh`** — 65+ feature comparison test suite; generates `docs/test-results.md` with HermesClaw × NemoClaw comparison
- **`docs/features.md`** — complete feature reference covering sandbox security, policy management, inference routing, sandbox lifecycle, Hermes capabilities, messaging gateway, memory, skills, CLI, Python SDK, Docker deployment
- **`docs/test-results.md`** — auto-generated comparison table (regenerated by `./scripts/test.sh`)
- **GPU Docker profile** — `docker compose --profile gpu up` using `llama.cpp:server-cuda`
- **Persistent skills volume** — `hermesclaw-skills` named volume so self-created skills survive container restarts
- **Privacy threshold env var** — `HERMES_PRIVACY_THRESHOLD` for sensitivity-based inference routing
- **Approval mode env var** — `HERMES_APPROVAL_MODE` (manual/smart/off)
- **`CONTRIBUTING.md`** — full contributor guide with dev setup, PR process, code standards, testing instructions
- **`CHANGELOG.md`** — this file
- **`CODE_OF_CONDUCT.md`** — Contributor Covenant v2.1
- **GitHub issue templates** — Bug Report, Feature Request
- **GitHub PR template** — checklist-based PR template
- **GitHub Actions CI** — YAML validation, shellcheck, test suite, Docker build check

### Changed
- **OpenShell policy YAML** — rewritten to correct `version: 1` schema with `filesystem_policy`, `landlock`, `process`, `network_policies` (L7 endpoint rules with `method`/`path` filters, binary glob matching)
- **OpenShell profile YAML** — updated with correct fields, inline inference provider switching docs, hot-reload instructions
- **`docker-compose.yml`** — unique container names for CPU/GPU variants (was: both named `llama-server`, now `llama-server-cpu` / `llama-server-gpu`); added skills volume, gateway port, healthcheck for hermesclaw service
- **`configs/hermes.yaml.example`** — expanded from minimal stub to full config covering gateway, memory, skills, toolsets, MCP, sessions, display, personalities
- **`.env.example`** — added all missing variables: `CTX_SIZE`, `LLAMA_PORT`, `HERMESCLAW_PORT`, `TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, `SLACK_BOT_TOKEN`, `HERMES_PRIVACY_THRESHOLD`, `HERMES_APPROVAL_MODE`
- **`scripts/start.sh`** — added `--gpu` and `--policy` flags, validates policy file exists and OpenShell gateway is running before attempting sandbox create
- **`scripts/hermesclaw`** — default policy changed from `default` to `strict` (safer default); `cmd_chat` simplified to avoid fragile stdin file upload

### Fixed
- **docker-compose.yml** — duplicate `container_name: llama-server` for CPU and GPU services (would conflict if both profiles ever ran simultaneously)
- **scripts/doctor.sh** — `python3` JSON parsing now has `jq` → `python3` → `grep` fallback chain; no hard dependency on any single tool

---

## [0.1.0] — 2026-03-31

### Added
- Initial release: Hermes Agent (NousResearch) running inside NVIDIA OpenShell
- `Dockerfile` — debian:bookworm-slim + official Hermes install script
- `docker-compose.yml` — llama-server (CPU) + hermesclaw services
- `openshell/hermesclaw-policy.yaml` — initial sandbox policy
- `openshell/hermesclaw-profile.yaml` — sandbox profile with inference routing
- `configs/hermes.yaml.example` — basic Hermes config pointing at `inference.local`
- `configs/persona.yaml.example` — user persona template
- `.env.example` — environment variable template
- `scripts/setup.sh` — one-time setup (Docker build + OpenShell policy/profile registration)
- `scripts/start.sh` — start sandbox or docker compose
- `scripts/status.sh` — quick status check
- `assets/banner.png` — project banner

[Unreleased]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/TheAiSingularity/hermesclaw/releases/tag/v0.1.0
