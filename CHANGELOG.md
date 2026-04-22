# Changelog

All notable changes to HermesClaw are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

*Changes staged for the next release go here.*

---

## [0.3.5] — 2026-04-22

Bug-fix for v0.3.4. Install.sh's symlink-into-`/usr/local/bin` path was broken in a way the pre-release tests missed; end-to-end smoke-test of the installer caught it.

### Fixed

- **`hermesclaw` CLI failed when invoked via a symlink ([scripts/hermesclaw](scripts/hermesclaw)).** v0.3.4's `install.sh` symlinks the script into `/usr/local/bin/hermesclaw`, but the script computed `POLICY_DIR` from `dirname(${BASH_SOURCE[0]})/../openshell` — when invoked through the symlink, that resolved to `/usr/local/openshell`, which doesn't exist. `hermesclaw version`, `help`, `policy-list`, and every other subcommand exited immediately with `cd: /usr/local/openshell: No such file or directory`. Running `./scripts/hermesclaw` directly from the cloned repo was unaffected.
- Added a portable symlink-resolution loop at the top of `scripts/hermesclaw`. Works on macOS (BSD `readlink`) and Linux (GNU `readlink`) without coreutils or `realpath`.

### Upgrade notes

Anyone who ran the v0.3.4 one-liner should either re-run it (install.sh updates the cloned repo in place) or `git -C ~/.hermesclaw pull` to pick up the fix.

---

## [0.3.4] — 2026-04-22

Distribution polish. First release with a one-line install and a published container image.

### Added

- **One-command install** — `curl -fsSL https://raw.githubusercontent.com/TheAiSingularity/hermesclaw/main/scripts/install.sh | bash` clones the repo to `~/.hermesclaw`, pulls the prebuilt image from GHCR, bootstraps `.env`, and symlinks the `hermesclaw` CLI to `/usr/local/bin`. Non-interactive, idempotent, falls back gracefully when `/usr/local/bin` isn't writable (tries sudo, then prints PATH instructions).
- **Prebuilt multi-arch image** — published to GitHub Container Registry at `ghcr.io/theaisingularity/hermesclaw:<version>` and `:latest`. Built for `linux/amd64` and `linux/arm64` so it runs on Apple Silicon Macs and NVIDIA DGX Spark out of the box (no local Docker build required — that still works too).
- **`.github/workflows/release.yml`** — on `v*` tag pushes, builds the multi-arch image with `docker buildx` + QEMU and pushes to GHCR with OCI labels including the pinned Hermes version. Supports `workflow_dispatch` for manual candidate builds.

### Changed

- **README Quick Start** rewritten — primary path is now the one-liner install. "Build from source" is a secondary section for contributors. OpenShell path kept at the end.
- **README version badge** bumped to 0.3.4.
- **`scripts/hermesclaw`** — `VERSION` bumped to `0.3.4`.
- **CI shellcheck** now lints `scripts/install.sh` alongside the other shell scripts.

---

## [0.3.3] — 2026-04-22

Reproducibility and upstream-tracking release. No behavior changes; makes the stack easier to pin down and debug across hosts.

### Added

- **`docs/compatibility.md`** — tested-against matrix for Hermes Agent, OpenShell, NemoClaw blueprint, llama.cpp, Debian base image, and host OS; includes a field-reports section (first entries: [@ppritcha](https://github.com/ppritcha) on DGX Spark, maintainer on macOS/Apple Silicon) and a documented bump policy for each dependency.
- **`/etc/hermes-version`** written inside the Docker image, recording the Hermes tag the image was built against. Readable via `docker exec hermesclaw cat /etc/hermes-version`.
- **`scripts/doctor.sh`** — new "hermes version (pinned)" check that reads `/etc/hermes-version` from the running container (or a throwaway container on the image) so field reports automatically include the exact Hermes version.

### Changed

- **Hermes Agent install is now pinned** to `v2026.4.16` via `ARG HERMES_VERSION` in the [Dockerfile](../Dockerfile) and `scripts/install.sh --branch "${HERMES_VERSION}"` (previously pulled `main` on every build, producing non-deterministic images). Override at build time with `docker build --build-arg HERMES_VERSION=vYYYY.M.D`. Bump policy and rationale documented in `docs/compatibility.md`.
- **`scripts/hermesclaw`** — `VERSION` bumped to `0.3.3`.

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

[Unreleased]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.3.5...HEAD
[0.3.5]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.2.0...v0.3.1
[0.2.0]: https://github.com/TheAiSingularity/hermesclaw/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/TheAiSingularity/hermesclaw/releases/tag/v0.1.0
