# Changelog

All notable changes to HermesClaw are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

*Changes staged for the next release go here.*

---

## [0.3.2] — 2026-04-22

Bug-fix release addressing field reports from DGX Spark testing (thanks [@ppritcha](https://github.com/ppritcha) for all three).

### Fixed

- **`hermes` binary now reachable by the sandbox user ([#3](https://github.com/TheAiSingularity/hermesclaw/issues/3)).** Hermes was installed under `/root/.local/bin/hermes` and its venv under `/root/.hermes/hermes-agent/venv/`, both inaccessible to the unprivileged `sandbox` user that OpenShell switches to for interactive sessions (`openshell sandbox connect` hit `Permission denied`; the `CMD` entrypoint worked only because it launches as root before the user policy is applied). The Dockerfile now copies the binary to `/usr/local/bin/hermes` (on default PATH), copies the venv to `/opt/hermes-venv`, rewrites the binary's shebang to point at the relocated python3, and `chmod 755 /root` so the sandbox user can traverse into the data directory. Policy `binaries:` paths in all four policy files updated from `/root/.local/bin/hermes` to `/usr/local/bin/hermes`.
- **`hermesclaw chat` no longer crashes in OpenShell mode ([#1](https://github.com/TheAiSingularity/hermesclaw/issues/1)).** The old code invoked `openshell sandbox connect "$NAME" -- bash -c "..."`, but `openshell sandbox connect` does not accept `-- COMMAND` syntax (that is only supported on `sandbox create`). Docker users saw no error; OpenShell users got a cryptic `error: unexpected argument 'bash' found`. `cmd_chat` now prefers the Docker path, then host-installed `hermes`, and as a last resort pipes the chat invocation through `openshell sandbox connect`'s stdin. On failure it prints an explicit workaround (`openshell sandbox connect <name>`, then `hermes chat -q ...` inside) with a link to the tracking issue rather than the cryptic OpenShell error.
- **`scripts/hermesclaw` `VERSION` ([#2](https://github.com/TheAiSingularity/hermesclaw/issues/2))** — bumped to `0.3.2` (was stuck at `0.2.0` through the v0.3.0 and v0.3.1 releases).

---

## [0.3.1] — 2026-04-21

Consolidated release covering all work between v0.2.0 and today. Supersedes the unreleased v0.3.0 and v0.4.0 development labels, which never tagged a release — their content is folded in below.

### Fixed
- **OpenShell policy YAML schema (corrects v0.3.0 attempt)** — all 4 policy files (`hermesclaw-policy.yaml`, `policy-strict.yaml`, `policy-gateway.yaml`, `policy-permissive.yaml`) now match the authoritative NemoClaw v0.1.0 reference blueprint (`~/.nemoclaw/source/nemoclaw-blueprint/policies/openclaw-sandbox.yaml`). The v0.3.0 development work shipped an invented schema (`access_level`, `landlock.enabled`, `protocol: https`, `rest:` blocks, bare glob `binaries:`) that OpenShell rejects at parse time. v0.3.1 reverts to the real schema:
  - `process.user/group` → `process.run_as_user/run_as_group`
  - `landlock.enabled: true` → `landlock.compatibility: best_effort`
  - Endpoint fields: restored `enforcement: enforce` + `tls: terminate` + explicit `protocol: rest` stanza
  - REST rules: restored `rules:` with `{allow: {method: ..., path: ...}}` shape (not `rest:` + `access_level`)
  - `binaries:` list items restored to `{path: "..."}` objects (not bare globs)
  - Binary bound to `/root/.local/bin/hermes` throughout (Python), the one intentional divergence from the blueprint's Node-based `/usr/local/bin/node`.
- **`scripts/setup.sh`** — now registers an OpenShell inference provider (`local-llama`) and inference route on first run (mirrors NVIDIA/NemoClaw's own `setup.sh`). Previously only built the Docker image. Skipped silently when OpenShell is absent.
- **`scripts/setup.sh`** — bootstraps `.env` from `.env.example` on first run.
- **`scripts/status.sh`** — `openshell sandbox status` → `openshell sandbox get` (the `status` verb was never a valid OpenShell CLI command).
- **`docker-compose.yml`** — added `extra_hosts: host.docker.internal:host-gateway` so the container can reach a host-side `llama-server` on native Linux Docker. macOS/Windows Docker Desktop already maps this; Linux did not.
- **`scripts/hermesclaw`** — version string bumped to `0.2.0` (was stuck at `0.1.0` despite being the v0.2.0 release; bumped again on this release).

### Added
- **`docs/kernel-sandbox.md`** — a grounded reference for what "kernel-level sandbox" means in HermesClaw: the four enforcement layers, what is actually configured in the YAMLs (not marketing), honest gaps (seccomp inherited from OpenShell rather than owned locally; Landlock is `best_effort`; WebSockets opaque to proxy; etc.), threat model, and a 15-item improvement roadmap.
- **`docs/use-cases/`** — seven end-to-end deployment guides, one per persona:
  - `01-researcher/` — Docker + Telegram gateway + weekly arXiv digest cron
  - `02-developer/` — Docker + VS Code ACP integration + Git MCP
  - `03-home-automation/` — Docker + Home Assistant MCP + Telegram bot
  - `04-data-analyst/` — Docker + Postgres MCP + daily anomaly detection
  - `05-small-business/` — Docker + gateway policy + Slack support bot
  - `06-privacy-regulated/` — OpenShell sandbox + strict policy (HIPAA/legal/compliance)
  - `07-trader/` — Docker + Qwen-7B + Telegram market alerts
  - `README.md` — index with quick-picker table + NemoClaw compatibility matrix across all 7 use cases
- **`skills/`** — pre-built Hermes skills library (native SKILL.md format, installable in one command):
  - `research-digest/` — weekly arXiv + web paper digest to Telegram
  - `code-review/` — local code review using project conventions from memory
  - `home-assistant/` — natural language smart home control via HA MCP
  - `anomaly-detection/` — daily Postgres metric monitoring; flags > 2σ deviations
  - `slack-support/` — Slack support bot with knowledge base and escalation routing
  - `market-alerts/` — watchlist threshold monitoring with Telegram alerts
- **`skills/install.sh`** — interactive installer; copies skills to `~/.hermes/skills/`.
- **`skills/anomaly-detection/scripts/detect.py`** — z-score anomaly computation helper (stdlib only).
- **`skills/market-alerts/scripts/monitor.py`** — price threshold comparison helper (stdlib only).
- **`README.md`** — "Use Cases" and "Skills Library" sections with install commands; TOC; architecture image.
- **Sequential comparison test infrastructure** — `scripts/test-setup.sh` + `test-uc-01.sh` through `test-uc-07.sh`, all writing results to `docs/test-results-uc.md`.

### Changed
- **NemoClaw comparison tables corrected** across the README and all 7 use-case guides:
  - Provider support: NemoClaw supports OpenAI, Anthropic, Gemini, NVIDIA NIM (not Nemotron-only).
  - Tool count: OpenClaw (the agent NemoClaw wraps) has 25+ tools and messaging channels (not ~10).
  - Telegram/Slack/Discord: NemoClaw/OpenClaw has native gateway support — corrected from "❌" to "✅".
  - macOS local inference: NemoClaw has a confirmed DNS bug (issue #260) breaking local models on macOS — added as explicit caveat.
  - HermesClaw advantages clarified: persistent MEMORY.md/USER.md, self-improving skills (DSPy+GEPA), MCP server support, local inference on macOS.
- **Branding** — removed "world's first" / "nobody had done it" language from README, CONTRIBUTING.md, and profile YAML; replaced with a neutral description of this being a community implementation built on NVIDIA OpenShell and NousResearch Hermes Agent.
- **`docs/test-results.md`** — regenerated 2026-04-01; llama.cpp health check now reports `✅ responding` (previously skipped on --quick).
- **`.gitignore`** — excludes `docs/promotion.md` (personal promo content, not repo-appropriate).

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

[Unreleased]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.2.0...v0.3.1
[0.2.0]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/TheAiSingularity/hermesclaw/releases/tag/v0.1.0
