# Kernel-Level Sandbox — Concept, Implementation, Gaps

This document explains what "kernel-level sandbox" means in HermesClaw, what is actually implemented today (read the YAML, not the marketing), and what is missing or could be improved.

It is meant for people who will deploy HermesClaw in production and need to know exactly what the sandbox guarantees — not a pitch deck.

---

## Table of Contents

1. [What a Kernel-Level Sandbox Is — And Why It Matters](#what-a-kernel-level-sandbox-is--and-why-it-matters)
2. [The Four Layers in Theory](#the-four-layers-in-theory)
3. [What HermesClaw Implements Today](#what-hermesclaw-implements-today)
4. [Honest Gaps — What HermesClaw Does Not Implement](#honest-gaps--what-hermesclaw-does-not-implement)
5. [Threat Model — What the Sandbox Protects Against](#threat-model--what-the-sandbox-protects-against)
6. [What the Sandbox Does Not Protect Against](#what-the-sandbox-does-not-protect-against)
7. [Improvement Roadmap](#improvement-roadmap)
8. [Further Reading](#further-reading)

---

## What a Kernel-Level Sandbox Is — And Why It Matters

Most "AI agent safety" today is implemented inside the agent: system prompts, guardrail models, refusal classifiers, approval dialogs. All of these live in **userspace** and run in the same process as the agent. If the agent is compromised — prompt injection, a malicious skill, a supply-chain attack in a tool — the guardrails go with it.

A kernel-level sandbox inverts that relationship. Security rules live in the **kernel**, outside the agent's process space. The agent cannot read the rules, cannot modify them, cannot bypass them. When the agent asks the kernel to do something the rules forbid, the syscall returns `EPERM` — the agent sees a denied operation, not a disabled one.

| Approach | Location | Can a compromised agent bypass it? |
|---|---|:---:|
| System prompts / guardrails | Agent process | Yes — prompts are just text the model can ignore |
| Approval dialogs / tool gates | Agent process | Yes — agent controls the gate |
| Docker container isolation | Kernel (namespaces) | Partial — root-in-container can escape in some configs |
| VM isolation | Hypervisor | No — but heavy, slow startup |
| **Kernel LSM + seccomp** | **Kernel (out-of-process)** | **No — rules enforced below the agent** |

This matters more as agents gain autonomy. A chatbot that can only return text is a low-blast-radius component. An agent that can run shell commands, read files, make HTTP calls, and install skills is a very different risk surface.

---

## The Four Layers in Theory

NVIDIA's OpenShell model layers four enforcement mechanisms on top of a Linux container:

```
┌─────────────────────────────────────────────────────────────────┐
│  Hermes Agent (Python process)                                  │
│  - runs as non-root user                                        │
│  - sees only the paths the sandbox allows                       │
│  - sees only the network routes the sandbox allows              │
│  - sees only its own credentials, not backend keys              │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Filesystem   │   Landlock LSM  (kernel module)              │
│  2. Process      │   Seccomp BPF   (syscall filter)             │
│  3. Network      │   OPA + HTTP CONNECT proxy (out-of-process)  │
│  4. Inference    │   Privacy router (credential strip + inject) │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
                           Linux kernel
```

Each layer is described briefly below. Only the combination gives meaningful guarantees — any one of them alone is weak.

### Layer 1 — Filesystem (Landlock LSM)

**Landlock** is a Linux Security Module (kernel feature since Linux 5.13) that lets an unprivileged process declare, *"from now on, I can only read/write these paths."* Once declared, the restriction is inherited by all child processes and cannot be lifted. The enforcement happens in the kernel's VFS layer — a `open()` syscall to a disallowed path returns `EACCES` even for root.

Landlock is path-based and additive-only. The process declares what it wants to give up, the kernel enforces it.

### Layer 2 — Process (Seccomp BPF)

**Seccomp** (secure computing mode) filters syscalls at the kernel boundary using a BPF program. OpenShell installs a seccomp profile that denies the dangerous syscalls an agent has no business making:

- `ptrace` — debugger attach; prevents a compromised process from reading another process's memory
- `mount` / `umount2` — mount manipulation; prevents escaping via a bind mount
- `kexec_load` — load a new kernel; a creative privilege escalation
- `perf_event_open` — performance counters are a side-channel
- `process_vm_readv` / `process_vm_writev` — cross-process memory read/write

A denied syscall returns `EPERM`. The agent cannot turn seccomp off because the filter is installed by the parent (OpenShell) before the agent process starts.

Seccomp is combined with **unprivileged user** (`run_as_user: sandbox`) so that even if a kernel bug lets a syscall through, the effective UID is not root.

### Layer 3 — Network (OPA + HTTP CONNECT proxy)

Classic network firewalls (iptables / nftables) work at layer 3/4 — IP addresses and ports. That's not precise enough for an agent: `api.github.com` and `api.example.com` might share the same CDN IP. OpenShell's network enforcement runs at **layer 7** — it terminates TLS, inspects the HTTP method and path, and applies policy per request.

- Agent traffic is transparently routed through a local proxy.
- The proxy speaks OPA (Open Policy Agent) to evaluate each request against the active policy.
- Rules are `(host, port, method, path-glob) → allow | deny`.
- WebSocket connections use a `CONNECT` tunnel (`access: full`) with no L7 filtering — the proxy cannot inspect opaque bytes inside an upgraded connection.
- Each policy binds to a **binary path** — only the `hermes` executable can use the rule, not an arbitrary `curl` or `wget` the agent might drop into `/tmp/`.

This layer is **hot-reloadable** — policy can change without restarting the agent.

### Layer 4 — Inference (Privacy router)

The inference layer isn't about syscalls or network, it's about credentials. OpenShell's **privacy router** intercepts every call the agent makes to `inference.local`. The agent only ever sees a URL like `http://inference.local/v1/chat/completions` — it does **not** see the real backend (OpenAI, Anthropic, NVIDIA NIM, local llama.cpp) and does **not** see the API key.

The router:
1. Strips any credentials the agent tries to attach.
2. Forwards the request to the backend configured by the operator (not the agent).
3. Injects the backend credential from OpenShell's keystore.
4. Returns the response.

Implication: an agent compromised by prompt injection cannot exfiltrate its backend's API key, because it does not have one. It has a URL that the kernel-level proxy routes.

---

## What HermesClaw Implements Today

This section is grounded in the files in [openshell/](../openshell/). Claims here are verifiable by reading YAML. Claims *not* in YAML are explicitly called out in the next section.

### Layer 1 — Filesystem: IMPLEMENTED

All four policy files declare filesystem policy using OpenShell's `filesystem_policy` block:

```yaml
filesystem_policy:
  include_workdir: true
  read_only:
    - /usr
    - /lib
    - /lib64
    - /bin
    - /etc/ssl
    - /etc/resolv.conf
    - /etc/passwd
    - /etc/group
    - /sandbox/knowledge     # user docs (ro mount)
    - /sandbox/configs       # persona + config (ro mount)
  read_write:
    - /opt/hermes-data       # memories, skills, auth
    - /sandbox               # working dir
    - /tmp
```

Plus `landlock: compatibility: best_effort` — OpenShell enforces the paths above via Landlock where the host kernel supports it. `best_effort` means: use Landlock if present, warn otherwise. A `hard_requirement` alternative exists but is not currently configured.

Result: Hermes can read the standard system libraries and its working directory, and write only to its own state directory plus `/tmp`. A write to `/etc/cron.d/` returns `EACCES`.

### Layer 2 — Process: PARTIALLY IMPLEMENTED

All four policy files declare:

```yaml
process:
  run_as_user: sandbox
  run_as_group: sandbox
```

This gives unprivileged user enforcement — `hermes` runs as UID `sandbox`, not root.

**What is NOT in the HermesClaw policy YAML:** a `seccomp` stanza listing the specific syscalls to block. The docs and marketing reference `ptrace`, `mount`, `kexec_load`, `perf_event_open`, and `process_vm_readv/writev` as blocked — but that enforcement comes from **OpenShell's default seccomp profile**, not from HermesClaw's policy. HermesClaw inherits it; it does not configure it.

This is an honest limitation: HermesClaw's claim "we block dangerous syscalls" is accurate *because OpenShell does it for us*, not because HermesClaw does it independently. If OpenShell ships a looser default in a future version, HermesClaw does not override it.

See the roadmap section for what a HermesClaw-owned seccomp profile would look like.

### Layer 3 — Network: IMPLEMENTED (and this is the most mature layer)

Network policy is where HermesClaw has done the most concrete work. Each policy YAML defines named `network_policies` sections, each containing endpoints with per-host, per-port, per-protocol rules:

```yaml
network_policies:
  inference_local:
    endpoints:
      - host: inference.local
        port: 443
        protocol: rest
        enforcement: enforce
        tls: terminate
        rules:
          - allow: { method: "*", path: "/**" }
    binaries:
      - { path: /usr/local/bin/hermes }
```

- **Binary-bound:** each policy lists the executable (`/usr/local/bin/hermes`) that may use it. A `curl` dropped into `/tmp/` cannot use these rules.
- **Method + path glob:** for example, the Telegram policy only allows `GET/POST` on `/bot*/**` — nothing else.
- **`tls: terminate`:** the proxy terminates TLS, enabling L7 inspection.
- **`access: full` for WebSockets:** Discord's gateway and Slack's Socket Mode bind as `access: full` because the proxy cannot filter post-upgrade WebSocket frames.

Three escalating policy presets are defined:

| Preset | File | Endpoints allowed |
|---|---|---|
| `strict` | [policy-strict.yaml](../openshell/policy-strict.yaml) | `inference.local` only |
| `gateway` | [policy-gateway.yaml](../openshell/policy-gateway.yaml) | + `api.telegram.org`, `discord.com`, `gateway.discord.gg`, `cdn.discordapp.com`, `media.discordapp.net` |
| `permissive` | [policy-permissive.yaml](../openshell/policy-permissive.yaml) | + `slack.com` (+ API + hooks + WSS), `huggingface.co` + LFS CDN, `github.com` + API + raw, `duckduckgo.com` (GET only) |

Policy can be hot-swapped on a running sandbox:

```bash
hermesclaw policy-set gateway
# or directly:
openshell policy set hermesclaw-1 --policy openshell/policy-gateway.yaml --wait
```

### Layer 4 — Inference: IMPLEMENTED via OpenShell profile

HermesClaw's sandbox profile ([openshell/hermesclaw-profile.yaml](../openshell/hermesclaw-profile.yaml)) configures the inference router:

```yaml
inference:
  provider: local
  endpoint: "http://127.0.0.1:8080/v1"

env:
  - name: OPENAI_BASE_URL
    value: "http://inference.local/v1"
  - name: OPENAI_API_KEY
    value: "not-needed"           # OpenShell injects real creds
```

The agent's `OPENAI_API_KEY` is set to the literal string `not-needed` — that is intentional. The real backend key lives in OpenShell's keystore and is injected by the router at egress. Hot-swap the provider with `openshell inference set --provider <name>`.

### Other concrete integration work (not a security layer, but worth knowing)

- **[scripts/hermesclaw](../scripts/hermesclaw)** — CLI that wraps `openshell sandbox create --policy ... -- hermes gateway`, handles policy-set / start / stop / doctor.
- **[scripts/setup.sh](../scripts/setup.sh)** — registers policies and profile with OpenShell on first run.
- **[scripts/doctor.sh](../scripts/doctor.sh)** — end-to-end diagnostic: kernel version, Landlock presence, OpenShell gateway, sandbox state.
- **[docker-compose.yml](../docker-compose.yml)** — a *fallback* mode on hosts without OpenShell (macOS, no NVIDIA). Runs Hermes in a Docker container with namespace + capability-drop isolation. This is **not** kernel-level enforcement — it's a best-effort substitute.

---

## Honest Gaps — What HermesClaw Does Not Implement

This is deliberately a dedicated section, because it matters more than the marketing.

### 1. No explicit seccomp profile in HermesClaw's repo

HermesClaw's policy YAMLs do not contain a `seccomp` stanza. Syscall filtering (`ptrace`, `mount`, `kexec_load`, etc.) is inherited from OpenShell's built-in default. If a deployment needs a specific, auditable syscall deny list, that list currently lives in OpenShell's source, not in HermesClaw.

**Why it matters:** operators doing their own threat modeling cannot point to a file in this repo and say "these syscalls are blocked." They have to trust the upstream default.

### 2. Landlock is `best_effort`, not `hard_requirement`

All four policies use `landlock: compatibility: best_effort`. If the host kernel lacks Landlock (older than 5.13, or Landlock disabled at boot), the sandbox still starts — with filesystem enforcement degraded or absent. Production deployments that require Landlock should change this to `hard_requirement`.

**Why it matters:** the sandbox can silently start in a weaker state than an operator expects.

### 3. WebSocket traffic is opaque to the proxy

Discord's `gateway.discord.gg` and Slack's `wss-primary.slack.com` use `access: full` (CONNECT tunnel). Once upgraded, the proxy sees encrypted bytes. A malicious tool using the Discord gateway could in principle exfiltrate data over the WebSocket frame stream.

**Why it matters:** the "binary-bound + method/path" granularity does not apply to post-upgrade traffic. This is a known limitation of HTTP-CONNECT-style egress control, not a HermesClaw bug.

### 4. No audit log shipper

OpenShell itself writes audit logs, but HermesClaw does not ship a sidecar or script to forward them to a SIEM (Splunk / Datadog / Elastic / journald). Compliance deployments that need a tamper-evident audit trail must wire this themselves.

### 5. Docker fallback mode is NOT kernel-level

On macOS (and on Linux without OpenShell), [docker-compose.yml](../docker-compose.yml) runs Hermes in a regular Docker container. This gives you:
- Linux namespaces (pid, net, mnt, user) — useful
- Capability drops — useful
- **No** Landlock (macOS kernel does not have it)
- **No** OpenShell seccomp profile (Docker applies its own default)
- **No** OPA + L7 proxy — egress is at Docker network level, not per-request

Docker mode is honest isolation, but it is not kernel-level in the sense this document uses. The [README](../README.md) is explicit about this; the test runner [scripts/test-uc-06.sh](../scripts/test-uc-06.sh) refuses to claim full enforcement on macOS and prints `warn "PARTIAL TEST: macOS cannot enforce Landlock/Seccomp."`.

### 6. Hardware validation is unconfirmed

[CONTRIBUTING.md](../CONTRIBUTING.md) and the README explicitly solicit field reports from users with real NVIDIA OpenShell hardware. As of v0.3.0, HermesClaw's policies have been written against NVIDIA's NemoClaw v0.1.0 reference blueprint (the YAMLs' inline comments cite `~/.nemoclaw/source/nemoclaw-blueprint/policies/openclaw-sandbox.yaml`), but end-to-end runtime validation on production OpenShell installations has not been publicly reported.

### 7. No observability shipped

No structured logs emitted by HermesClaw itself. No Prometheus exporter, no OpenTelemetry traces, no dashboard. A compromised agent that obeys policy can still behave in operationally unhealthy ways (context bloat, runaway tool loops, memory inflation) and the operator gets no visibility.

### 8. No policy diff tool

Changes to `openshell/*.yaml` are reviewed manually in PRs. There is no `hermesclaw policy-diff old.yaml new.yaml` that explains in English "this change adds an egress endpoint; this change allows a method that was previously blocked." Policy PRs are the highest-risk changes in the repo and deserve a tool.

### 9. Memory volume is read-write for the agent

`/opt/hermes-data` is read-write in all policies (memories, skills, auth). This is intentional — persistent memory is a feature — but it means a compromised agent can poison its own future sessions by editing `/opt/hermes-data/memories/MEMORY.md`. There is no write-ahead integrity check or append-only mode.

### 10. No per-skill policy scoping

Policies are bound to the `hermes` binary as a whole. A skill with a `web_search` tool runs under the full `permissive` policy; there is no way to say "this skill can use Telegram but not GitHub." Policy granularity stops at the binary.

---

## Threat Model — What the Sandbox Protects Against

HermesClaw's sandbox is designed against these threats. When the four layers are in place on Linux + OpenShell + a supported kernel:

| Threat | Mitigated? | How |
|---|:---:|---|
| Prompt injection tells agent to exfiltrate API keys | Yes | Privacy router — agent does not hold backend keys |
| Agent runs malicious shell code to read `/etc/shadow` | Yes | Landlock — `/etc/shadow` is not in `read_only` or `read_write` |
| Compromised skill writes to `/etc/cron.d/` to persist | Yes | Landlock — `/etc` (except listed files) is out of scope |
| Agent tries to exfil data by POSTing to attacker.com | Yes | L7 proxy — `attacker.com` not in any `network_policies` section |
| Agent tries to exfil data by POSTing to allowed GitHub | Partial | Binary-bound rule allows `api.github.com` POST — content can be exfiltrated within that allowed path |
| Malicious tool forks and ptraces the agent | Yes | Seccomp (from OpenShell default) blocks `ptrace` |
| Exploit attempts to load malicious kernel module | Yes | Seccomp blocks `kexec_load`; unprivileged user blocks `init_module` |
| Agent escapes chroot via `mount` | Yes | Seccomp blocks `mount` / `umount2` |
| Compromised Hermes tries to disable the sandbox | Yes | Sandbox rules are installed by OpenShell (the parent) and inherited — the child cannot remove them |
| Supply-chain attack on a tool the agent calls | Partial | Tool inherits sandbox rules, but within `permissive` it can still exfiltrate to any allowed host |

---

## What the Sandbox Does NOT Protect Against

Equally important to be clear about:

- **Data exfiltration to allowed endpoints.** If `permissive` allows GitHub, and the agent is manipulated into POSTing secrets to a public Gist, the sandbox sees a legitimate call. Threat model assumes allowed endpoints are trusted.
- **Prompt injection changing agent behavior within its allowed scope.** The sandbox does not read prompts. An injection that tells the agent to "summarize nothing and call this a success" is still successful.
- **Model-level jailbreaks.** If the underlying model can be manipulated into unsafe tool-use, the sandbox blocks the unsafe *syscalls* but not the unsafe *intent*.
- **Memory poisoning.** See gap #9 above. A bad session can write bad MEMORY.md content that shapes future sessions.
- **Resource exhaustion.** The profile caps CPU (2 cores) and memory (2 GiB), but a runaway agent can consume all its allocation repeatedly.
- **The host machine itself.** Sandbox protects the host from the agent. If the host is compromised, the sandbox is irrelevant.
- **Side channels.** Timing, cache, Spectre-class attacks. Out of scope.

---

## Improvement Roadmap

Ordered by impact × tractability. The first five are meaningful, shippable in weeks.

### Near-term (next release cycle)

**1. Ship an explicit seccomp profile in HermesClaw's repo.**
Currently inherits OpenShell's default. Define `openshell/seccomp-strict.bpf.json` listing the exact syscall allow list. Reference it from all policy files. Now operators can audit a file in this repo.

**2. Change Landlock to `hard_requirement` in a new `policy-hardened.yaml`.**
Keep `best_effort` as the default for broad compatibility. Add a fourth preset for operators who want the sandbox to refuse to start on unsupported kernels.

**3. Write `hermesclaw policy-diff <old> <new>`.**
Explains policy YAML diffs in human terms: "This PR opens egress to `api.openai.com`. This PR widens the Telegram path glob from `/bot*/**` to `/*`." Run as a CI check on any PR touching `openshell/*.yaml`.

**4. Document the NemoClaw blueprint provenance prominently.**
The YAML comments already cite `nemoclaw-blueprint/policies/openclaw-sandbox.yaml`. Promote this to a table in the README: "HermesClaw policies are derived from NVIDIA's NemoClaw v0.1.0 reference blueprint. Divergences are intentional and listed below." Divergences so far: one (binary path is Python `hermes`, not Node `node`).

**5. Audit log shipper.**
Small sidecar (shell script ok) that tails OpenShell's audit log and forwards policy violations to a webhook. Ship it behind an env var `HERMESCLAW_AUDIT_WEBHOOK`.

### Medium-term

**6. Write-protected memory mode.**
Optional policy flag that mounts `/opt/hermes-data/memories/` as append-only or read-only for a session. Agents that need to mutate memory can do so out-of-band via a human-approved step.

**7. Per-skill policy scoping.**
A skill manifest could declare which network policies it requires; the CLI enforces that only those are active during its execution. Requires broader changes — effectively a capability system layered on top of policies.

**8. WebSocket egress audit.**
Log size + timing of WebSocket frames going to `gateway.discord.gg` etc. Does not decrypt, but surfaces anomalies (agent sending 10 MB when normal usage is KB).

**9. Policy lint + schema validator.**
Standalone tool that validates `openshell/*.yaml` against the NemoClaw v0.1.0 schema. The v0.3.0 → v0.3.1 work fixed schema drift (`access_level`, `rest:`, `protocol: https`); a validator prevents that class of bug from recurring.

**10. Observability: Prometheus exporter.**
Expose counts for: policy violations, tool invocations by name, memory file mutations, syscall denies (from OpenShell audit). Lets operators graph agent behavior.

### Longer-term

**11. gVisor or Kata Containers as an alternative runtime.**
For hosts without OpenShell but that want stronger-than-Docker isolation. gVisor implements seccomp + syscall emulation in userspace; Kata runs each container in a lightweight VM. Either would give macOS and non-NVIDIA Linux hosts a path to near-kernel-level isolation.

**12. Policy-as-code review workflow.**
Treat `openshell/*.yaml` like database migrations. PR that widens egress requires approval from a named reviewer. Document the review criteria.

**13. Attested agent runtime.**
Remote attestation that a particular policy is in force on a particular sandbox. Needed for compliance scenarios (healthcare, legal) where proving the policy was active during a session is part of the audit.

**14. Formal model of the policy language.**
OPA policies are Rego-expressible; build a model that lets you answer "is there any reachable state where policy X allows egress to Y?" Useful for finding subtle mistakes in large permissive policies.

**15. Decouple from OpenShell.**
OpenShell is a valuable runtime, but it is not the only kernel-level option. Abstract HermesClaw's policy model from the specific OpenShell schema; support Landlock-only (no OpenShell), gVisor, or a custom Python agent harness directly. Removes a strategic dependency on NVIDIA.

---

## Further Reading

**Primary sources:**
- [Landlock LSM documentation](https://docs.kernel.org/userspace-api/landlock.html) — the Linux kernel's Landlock interface.
- [Seccomp BPF documentation](https://docs.kernel.org/userspace-api/seccomp_filter.html) — syscall filtering reference.
- [Open Policy Agent](https://www.openpolicyagent.org/docs/) — the policy engine used by OpenShell's network layer.
- [NVIDIA OpenShell docs](https://docs.nvidia.com/openshell/latest/) — the sandbox runtime HermesClaw integrates with.

**Relevant HermesClaw files:**
- [openshell/hermesclaw-policy.yaml](../openshell/hermesclaw-policy.yaml) — default baseline policy (same as strict).
- [openshell/policy-strict.yaml](../openshell/policy-strict.yaml) — inference-only preset.
- [openshell/policy-gateway.yaml](../openshell/policy-gateway.yaml) — + Telegram + Discord.
- [openshell/policy-permissive.yaml](../openshell/policy-permissive.yaml) — + Slack + HuggingFace + GitHub + DuckDuckGo.
- [openshell/hermesclaw-profile.yaml](../openshell/hermesclaw-profile.yaml) — bundles image + policy + mounts + inference.
- [docs/features.md](features.md) — summary feature reference.
- [docs/use-cases/06-privacy-regulated/](use-cases/06-privacy-regulated/) — end-to-end HIPAA / compliance scenario.
- [scripts/doctor.sh](../scripts/doctor.sh) — diagnostic that verifies layer-by-layer setup.

**Related external reading:**
- NVIDIA's [practical security guidance for sandboxing agentic workflows](https://developer.nvidia.com/blog/practical-security-guidance-for-sandboxing-agentic-workflows-and-managing-execution-risk/).
- [MITRE ATLAS](https://atlas.mitre.org/) — adversarial threat landscape for AI systems.
