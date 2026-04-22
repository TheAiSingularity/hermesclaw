# Compatibility Matrix

What upstream versions HermesClaw was last tested against, and how we manage the pins.

HermesClaw sits on top of several moving targets — Hermes Agent (upstream releases weekly), NVIDIA OpenShell, the NemoClaw policy blueprint, llama.cpp, and whatever kernel your host is running. This doc records the *last known good* combination and documents how we bump.

---

## Current pins

| Component | Tested version | Pinned in | Notes |
|---|---|---|---|
| **Hermes Agent** | `v2026.4.16` | [Dockerfile](../Dockerfile) `ARG HERMES_VERSION` | Installed via `scripts/install.sh --branch <tag>`. Override with `docker build --build-arg HERMES_VERSION=vYYYY.M.D`. |
| **NVIDIA OpenShell** | `0.0.34` (reported working by [@ppritcha](https://github.com/ppritcha) on DGX Spark with HermesClaw v0.3.2) | Not installed by HermesClaw — user installs on host. Declared in [`scripts/doctor.sh`](../scripts/doctor.sh). | Policy YAMLs parse against the v1 schema; `openshell sandbox connect` is used by `hermesclaw connect` and does NOT accept `-- COMMAND` (see [#1](https://github.com/TheAiSingularity/hermesclaw/issues/1)). |
| **NemoClaw blueprint** | `v0.1.0` reference (`~/.nemoclaw/source/nemoclaw-blueprint/policies/openclaw-sandbox.yaml`) | Inline citation comments in [`openshell/*.yaml`](../openshell/) | Our policies derive directly from this. One intentional divergence: `binaries: /usr/local/bin/hermes` instead of the blueprint's `/usr/local/bin/node` (Hermes is Python, OpenClaw is Node.js). |
| **llama.cpp** | Any version that speaks the OpenAI-compatible chat-completions API on `/v1/chat/completions` | Not pinned — user installs via `brew install llama.cpp` or builds from source | Backward-compatible API for the last several major versions. |
| **Debian base image** | `bookworm-slim` (floating) | [Dockerfile](../Dockerfile) line 1 | Floating tag accepted — security patches welcome. |
| **Host OS (OpenShell mode)** | Ubuntu 24.04 (DGX Spark reference) | — | Any Linux distro with Landlock LSM (kernel ≥ 5.13) and OpenShell support. |
| **Host OS (Docker mode)** | macOS 14+ (Apple Silicon), Ubuntu 22.04+, Windows 11 with Docker Desktop | — | Docker mode is a fallback when OpenShell is not available; kernel-level enforcement does not apply. |
| **Python (host)** | Not required on host | — | Hermes runs inside the container; host only needs Docker and optionally OpenShell. |

---

## Field reports

| HermesClaw | Host | Hermes | OpenShell | Reporter | Outcome |
|---|---|---|---|---|---|
| v0.3.2 | DGX Spark, Ubuntu | main (at time of test) | 0.0.34 | [@ppritcha](https://github.com/ppritcha) | Filed [#1](https://github.com/TheAiSingularity/hermesclaw/issues/1), [#2](https://github.com/TheAiSingularity/hermesclaw/issues/2), [#3](https://github.com/TheAiSingularity/hermesclaw/issues/3); all fixed in v0.3.2 |
| v0.3.2 | macOS 14 (Apple Silicon) | v2026.4.16 (via Docker pin) | N/A (Docker fallback) | Maintainer | `hermesclaw chat` + `doctor` pass; kernel-enforcement N/A |

If you test HermesClaw on a fresh platform/version combo, please open a PR adding a row here — or run `scripts/doctor.sh` and paste the output into a GitHub issue with the label `field-report`.

---

## Bump policy

- **Hermes Agent**: target monthly. Between releases, we hold the pinned tag. Bump process:
  1. Review upstream CHANGELOG for breaking changes.
  2. Local build with new tag: `docker build --build-arg HERMES_VERSION=vYYYY.M.D -t hermesclaw:bump .`
  3. Run `scripts/test.sh` (quick) against the bumped image.
  4. If green, update `ARG HERMES_VERSION` in Dockerfile + this table + CHANGELOG → PR → merge → tag a HermesClaw patch release.
  5. If red, open an issue, keep the old pin, and triage upstream diffs.
- **OpenShell / NemoClaw blueprint**: no automated bump. We rely on field reports (like Paul's DGX Spark run) to confirm continued compatibility; schema changes will be tracked as breaking events and trigger a major-version bump.
- **Debian base**: accepts rolling security updates within the `bookworm-slim` tag. Major version bump (e.g. to `trixie`) treated as a breaking change — requires its own validation PR.

---

## Reporting a compatibility issue

If HermesClaw fails in a known-working combination (or a new one), please include the following in your issue:

1. `./scripts/doctor.sh` output (includes detected versions)
2. Host OS + kernel: `uname -a`
3. OpenShell version: `openshell --version`
4. Docker version: `docker --version`
5. Which Hermes commit/tag was installed (check `/etc/hermes-version` inside the container, present from v0.3.3)
6. Policy preset in use (`hermesclaw status` shows it)

The bug report template at [.github/ISSUE_TEMPLATE/bug_report.md](../.github/ISSUE_TEMPLATE/bug_report.md) has fields for all of these.
