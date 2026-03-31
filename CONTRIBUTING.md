# Contributing to HermesClaw

Thank you for your interest in contributing. HermesClaw is the first open implementation of Hermes Agent (NousResearch) running inside NVIDIA OpenShell, and we want it to be the definitive reference for anyone who wants to run a sandboxed Hermes agent.

---

## Table of Contents

- [What we're building](#what-were-building)
- [Ways to contribute](#ways-to-contribute)
- [Development setup](#development-setup)
- [Making changes](#making-changes)
- [Testing](#testing)
- [Pull request process](#pull-request-process)
- [Code standards](#code-standards)
- [What we won't merge](#what-we-wont-merge)

---

## What we're building

HermesClaw has three layers:

1. **OpenShell integration** — policy YAML files, profile, and the `hermesclaw` CLI that wraps `openshell` commands
2. **Hermes configuration** — `hermes.yaml.example`, `persona.yaml.example`, Dockerfile, docker-compose
3. **Documentation** — feature reference, comparison table, test results

The most valuable contributions are in this order:
- **Correctness fixes** — wrong OpenShell policy schema, wrong CLI flags, broken commands
- **Real-world testing** — if you've run HermesClaw on actual NVIDIA hardware, test reports are gold
- **New policy presets** — for specific use cases (homeassistant, coding, research, etc.)
- **New platform policies** — Slack, WhatsApp, Signal network rules
- **Docs improvements** — anything that makes setup easier for a new user

---

## Ways to contribute

### Report a bug

Use the **Bug Report** issue template. Include:
- Output of `./scripts/doctor.sh`
- Output of `./scripts/hermesclaw doctor`
- Whether you're on OpenShell or Docker mode
- OS and OpenShell version

### Request a feature

Use the **Feature Request** template. The most welcome requests:
- Additional policy presets for specific use cases
- New platform integrations in the gateway policy
- Missing OpenShell CLI features in the `hermesclaw` wrapper
- Hermes configuration improvements

### Fix a bug or improve docs

Small fixes (typos, broken links, wrong commands) → open a PR directly.

Larger changes → open an issue first to discuss the approach.

### Improve OpenShell policy correctness

If you work at NVIDIA or have access to OpenShell internals, correctness fixes to the policy YAML schema are extremely valuable. The schema in `openshell/hermesclaw-policy.yaml` is our best effort from the public docs — if anything is wrong, please send a PR.

---

## Development setup

### Prerequisites

- Docker Desktop or Docker Engine
- bash 4+ (macOS: `brew install bash`)
- git
- Optional: NVIDIA GPU + OpenShell for full sandbox testing

### Clone and verify

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw

# Run diagnostics on the repo itself (no model needed)
./scripts/doctor.sh --quick

# Run the feature comparison test suite
./scripts/test.sh --quick
```

Both should complete without any `FAIL` entries (some `WARN` entries are expected if OpenShell/llama.cpp aren't installed).

### Validate YAML files

```bash
# Requires: pip install pyyaml
python3 -c "
import yaml, sys, glob
for f in glob.glob('**/*.yaml', recursive=True):
    try:
        yaml.safe_load(open(f))
        print(f'OK  {f}')
    except yaml.YAMLError as e:
        print(f'ERR {f}: {e}')
        sys.exit(1)
"
```

### Lint shell scripts

```bash
# Requires: brew install shellcheck (macOS) or apt-get install shellcheck (Linux)
shellcheck scripts/hermesclaw scripts/setup.sh scripts/start.sh scripts/status.sh scripts/doctor.sh scripts/test.sh
```

### Test Docker build

```bash
# Build the hermesclaw container image
docker build -t hermesclaw:latest .

# Verify Hermes is installed inside
docker run --rm hermesclaw:latest hermes version

# Full compose test (CPU mode)
cp .env.example .env
docker compose up -d
docker exec hermesclaw hermes status
docker compose down
```

---

## Making changes

### Branch naming

```
fix/policy-yaml-schema-v2
feat/homeassistant-policy-preset
docs/inference-routing-guide
test/live-gateway-test
```

Format: `<type>/<short-description>` using kebab-case.

Types: `fix`, `feat`, `docs`, `test`, `ci`, `refactor`, `chore`

### Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
fix(policy): correct Landlock compatibility field to best_effort
feat(preset): add homeassistant policy preset
docs(features): document voice note transcription for Discord
test(doctor): add jq fallback for JSON parsing
ci: add shellcheck to GitHub Actions
```

Format: `<type>(<scope>): <description in imperative mood>`

- Use present tense: "add", "fix", "update" — not "added", "fixed", "updated"
- Keep subject under 72 characters
- Add a body if the change is non-obvious

### One concern per PR

A PR that fixes a policy YAML schema issue should only fix that. A PR that adds a new preset should only add that preset and its documentation. Mixing unrelated changes makes review harder and slows merges.

---

## Testing

### Before every PR

Run both scripts and make sure there are no new `FAIL` entries:

```bash
./scripts/doctor.sh --quick
./scripts/test.sh --quick
```

### When changing policy YAML

Validate the schema:
```bash
python3 -c "import yaml; yaml.safe_load(open('openshell/hermesclaw-policy.yaml'))"
python3 -c "import yaml; yaml.safe_load(open('openshell/policy-strict.yaml'))"
python3 -c "import yaml; yaml.safe_load(open('openshell/policy-gateway.yaml'))"
python3 -c "import yaml; yaml.safe_load(open('openshell/policy-permissive.yaml'))"
```

### When changing shell scripts

```bash
shellcheck scripts/hermesclaw scripts/setup.sh scripts/start.sh scripts/status.sh scripts/doctor.sh scripts/test.sh
```

### When changing docker-compose.yml

```bash
docker compose config   # validates and prints resolved config
docker compose build    # builds the hermesclaw image
docker compose up -d    # starts the stack
./scripts/doctor.sh     # full check (no --quick)
docker compose down
```

### If you have OpenShell

If you have NVIDIA hardware and OpenShell installed, run the full test:

```bash
./scripts/setup.sh
./scripts/start.sh
./scripts/hermesclaw doctor
./scripts/hermesclaw chat "hello, verify you can respond"
./scripts/hermesclaw policy-set gateway
./scripts/hermesclaw stop
```

Include your `./scripts/doctor.sh` output in the PR body.

### Regenerate test-results.md

After any change to the test suite or feature status:
```bash
./scripts/test.sh --quick
git add docs/test-results.md
```

---

## Pull request process

1. **Fork** the repo and create a branch from `main`
2. **Make your changes** — one concern per PR
3. **Run the tests** — `./scripts/doctor.sh --quick` and `./scripts/test.sh --quick`
4. **Lint your scripts** — `shellcheck` on any modified `.sh` or `hermesclaw` files
5. **Validate any YAML** — `python3 -c "import yaml; yaml.safe_load(open('your-file.yaml'))"`
6. **Update docs** if your change adds or removes a feature — update `docs/features.md` and regenerate `docs/test-results.md`
7. **Open the PR** using the PR template — fill in all sections
8. **One approval** required before merge (from a maintainer or trusted contributor)

### PR checklist (enforced by template)

- [ ] `./scripts/doctor.sh --quick` passes with no new FAIL entries
- [ ] `./scripts/test.sh --quick` runs to completion
- [ ] `shellcheck` passes on any modified shell scripts
- [ ] All modified YAML files parse without errors
- [ ] `docs/test-results.md` regenerated if feature coverage changed
- [ ] `CHANGELOG.md` updated under `[Unreleased]`

---

## Code standards

### Shell scripts

- All scripts start with `#!/usr/bin/env bash`
- All scripts use `set -euo pipefail` (except where specific checks need to fail silently — document why)
- Variables are always quoted: `"$VAR"`, not `$VAR`
- Local variables declared with `local` inside functions
- Color codes defined as named variables at the top, never inline
- Error messages go to stderr: `echo "..." >&2`
- No hardcoded paths that won't work across environments — use `$SCRIPT_DIR` patterns
- No `cat` piped to `grep` — use `grep file` directly
- No backticks — use `$(...)` for command substitution

### YAML files

- 2-space indentation throughout
- Comments explain *why*, not *what* (the YAML already shows what)
- Every file has a header comment with purpose, usage, and reference link
- String values are quoted when they contain special characters
- Lists always use `-` with a space, never inline `[a, b, c]` for multi-item lists

### Documentation

- Markdown only — no HTML except where GitHub doesn't render Markdown (e.g., centered images)
- Code blocks always specify the language for syntax highlighting
- CLI commands are always wrapped in code blocks
- Links use relative paths for internal docs, absolute URLs for external
- No duplicate information — if something is in `docs/features.md`, link to it from `README.md` rather than copying it

---

## What we won't merge

- **Changes that weaken security without a documented justification** — e.g., opening up the network policy without a clear use case
- **Dockerfile changes that add root execution** — Hermes must run as an unprivileged user
- **Breaking changes to the `hermesclaw` CLI** without a deprecation path — existing users depend on `hermesclaw start/stop/status/connect`
- **Secret sprawl** — never add API keys, tokens, or credentials to any file that isn't in `.gitignore`
- **Untested changes** — if you can't run `./scripts/doctor.sh --quick` successfully, we can't merge
- **Large scope creep** — HermesClaw is specifically Hermes + OpenShell. We won't merge general-purpose Hermes improvements unrelated to the sandbox

---

## Questions?

Open a [Discussion](https://github.com/TheAiSingularity/hermesclaw/discussions) for anything that isn't a bug report or feature request. This is the right place for:
- "Is this the right approach for X?"
- "Has anyone gotten Y working?"
- "What's the roadmap for Z?"

---

## Credit

All contributors are listed in `CHANGELOG.md`. Significant contributors may be added to a `CONTRIBUTORS.md` file.
