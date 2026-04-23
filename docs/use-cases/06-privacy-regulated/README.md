# Use Case 06 — Privacy-Regulated Industry (Air-Gapped, OpenShell Sandbox)

**Stack**: OpenShell sandbox + strict policy + local llama.cpp inference

**What you get**: A kernel-enforced AI analysis environment where data cannot leave your network, all AI access is logged for audit, and the sandbox policy is verifiable by compliance teams. Suitable for healthcare (HIPAA), legal (privilege), finance (SOC 2 / PCI-DSS), and government workloads.

---

## What this looks like in practice

- Analyze patient records without any data leaving your network — OpenShell blocks all outbound traffic except to `inference.local`
- Contract review on privileged legal documents — the OS itself enforces that files cannot be exfiltrated
- Full immutable audit log: every file the agent reads, every network call attempted (and blocked), every inference request
- Compliance teams can read the OpenShell policy YAML and independently verify what the agent can and cannot do
- Air-gap mode: with no MCP servers and strict policy, the agent has zero outbound connectivity

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Linux host (Ubuntu 22.04+) | OpenShell requires Linux kernel 5.15+. macOS Apple Silicon supported via Colima. |
| NVIDIA OpenShell | [Install](https://docs.nvidia.com/openshell/latest/getting-started/install.html) — requires NVIDIA account |
| Docker Engine | On the same host |
| A GGUF model | Must be local — strict policy blocks NVIDIA/OpenAI API access. |
| Minimum 32 GB RAM | For document analysis with 14B+ models |

---

## How the sandbox enforces data containment

OpenShell operates at the kernel level, below the application. Even a fully compromised or malicious agent cannot bypass these controls:

| Layer | Mechanism | What it blocks |
|-------|-----------|----------------|
| **Network** | OPA + HTTP CONNECT proxy | All outbound traffic except `inference.local` (your local llama.cpp) |
| **Filesystem** | Landlock LSM | Agent can only read `~/.hermes/`, `/sandbox/knowledge/`, and `/tmp/`. Cannot read `/etc`, `/home`, or any other path |
| **Process** | Seccomp BPF | `ptrace`, `mount`, `kexec_load`, `perf_event_open`, `process_vm_readv/writev` blocked |
| **Inference** | Privacy router | Agent credentials stripped; no API keys or tokens visible inside the sandbox |

The strict policy in this repo (`openshell/policy-strict.yaml`) enforces network egress to `inference.local` only — no external hosts, no DNS queries outside the sandbox.

---

## Step-by-step setup

### Step 1 — Install OpenShell

```bash
# Requires NVIDIA account — follow official instructions
curl -fsSL https://www.nvidia.com/openshell.sh | bash
openshell --version   # confirm install
```

On macOS Apple Silicon, use Colima first:
```bash
brew install colima docker
colima start --memory 16 --cpu 4
# Then install OpenShell per the macOS docs
```

---

### Step 2 — Clone and build the image

```bash
git clone https://github.com/TheAiSingularity/hermesclaw
cd hermesclaw
cp .env.example .env
```

Download your model into `models/`. For compliance use cases, a larger model is recommended:
```bash
# Example: Qwen3-14B — strong at document analysis, runs on 32GB RAM CPU-only
MODEL_FILE=Qwen3-14B-Q4_K_M.gguf
```

Build the Docker image:
```bash
docker build -t hermesclaw:latest .
```

---

### Step 3 — Start llama.cpp on the host

The strict policy only allows inference calls to `inference.local` (the OpenShell router). Start llama.cpp on the host so OpenShell can route to it:

```bash
# CPU mode
docker run --rm -p 8080:8080 \
  -v ./models:/models:ro \
  ghcr.io/ggerganov/llama.cpp:server \
  -m /models/${MODEL_FILE} --port 8080 --host 0.0.0.0
```

Verify:
```bash
curl http://localhost:8080/health   # should return {"status":"ok"}
```

---

### Step 4 — Register the profile and start the sandbox

```bash
./scripts/setup.sh
# Registers hermesclaw profile with OpenShell

hermesclaw start --policy strict
# Creates sandbox hermesclaw-1 with the strict policy
```

---

### Step 5 — Verify network enforcement

```bash
# Inspect the running sandbox
openshell sandbox inspect hermesclaw-1

# Attempt to reach an external host from inside the sandbox (should fail)
openshell sandbox exec hermesclaw-1 -- curl -m 5 https://google.com
# Expected: connection refused or timeout — network policy blocks this

# Inference call should succeed (via inference.local)
hermesclaw chat "hello"
# Expected: Hermes responds (routes via inference.local → your llama.cpp)
```

---

### Step 6 — Drop documents into the knowledge directory

```bash
# Place sensitive documents here — mounted read-only into the sandbox
cp /path/to/sensitive-docs/* knowledge/

# Verify access from inside the sandbox
hermesclaw chat "List the documents in /sandbox/knowledge/"
```

---

### Step 7 — Review the audit log

```bash
# OpenShell logs every file access, network attempt, and syscall
openshell sandbox logs hermesclaw-1 --type audit | tail -50

# Export audit log for compliance review
openshell sandbox logs hermesclaw-1 --type audit --export audit-$(date +%Y%m%d).json
```

---

## Compliance-relevant policy details

The strict policy (`openshell/policy-strict.yaml`) enforces:

**Filesystem (Landlock):**
- Read/write: `/opt/hermes-data/` (memories, skills, config)
- Read/write: `/sandbox/` (working directory)
- Read/write: `/tmp/`
- All other paths: **denied at kernel level**

**Network:**
- `inference.local:80/443` — local llama.cpp via OpenShell router
- All other egress: **denied**

**Process:**
- Non-root user (`hermes:hermes`)
- Blocked syscalls: `ptrace`, `mount`, `umount2`, `kexec_load`, `perf_event_open`, `process_vm_readv`, `process_vm_writev`

This policy can be reviewed by your compliance team at `openshell/policy-strict.yaml`.

---

## Healthcare (HIPAA) configuration

For PHI workloads, additional hardening:

1. Use a **read-only Hermes memory** configuration — write skills only, not PHI:
   ```yaml
   memory:
     enabled: true
     write_whitelist: ["MEMORY.md", "USER.md"]  # never writes raw PHI
   ```

2. Mount clinical records **read-only**:
   ```yaml
   # In hermesclaw-profile.yaml
   mounts:
     - hostPath: "/srv/clinical-records"
       containerPath: "/sandbox/knowledge"
       readOnly: true   # Landlock enforces this
   ```

3. Retain audit logs for **6 years** per HIPAA §164.530(j):
   ```bash
   openshell sandbox logs hermesclaw-1 --type audit --export logs/$(date +%Y%m%d).json
   ```

---

## Legal (attorney-client privilege) configuration

For privileged matter files:

1. Create per-matter sandboxes with isolated policies:
   ```bash
   openshell sandbox create \
     --policy openshell/policy-strict.yaml \
     --name "matter-acme-2026" \
     -- hermes gateway
   ```

2. Mount only the files for that matter:
   ```bash
   # Mount only matter-specific directory
   openshell sandbox mount matter-acme-2026 \
     --host "/srv/matters/acme-corp" \
     --container "/sandbox/knowledge" \
     --readonly
   ```

3. The network policy guarantees documents cannot be exfiltrated via the agent.

---

## Verification checklist

```bash
# 1. Sandbox is running
openshell sandbox list | grep hermesclaw-1

# 2. Network enforcement confirmed
openshell sandbox exec hermesclaw-1 -- curl -m 3 https://ifconfig.me
# Expected: error (blocked)

# 3. Inference works
hermesclaw chat "Summarize the documents in /sandbox/knowledge in one paragraph"
# Expected: summary returned via local llama.cpp

# 4. Audit log is being written
openshell sandbox logs hermesclaw-1 --type audit | wc -l
# Expected: growing number of entries

# 5. Filesystem enforcement
openshell sandbox exec hermesclaw-1 -- cat /etc/passwd
# Expected: Permission denied (Landlock blocks this)
```

---

## NemoClaw comparison

| Feature | HermesClaw | NemoClaw |
|---------|:----------:|:--------:|
| OpenShell kernel-level sandbox | ✅ | ✅ |
| Immutable audit log | ✅ | ✅ |
| Local model (no data leaves network) | ✅ | ❌ |
| Offline / air-gapped mode | ✅ | ❌ |
| Document analysis tools | ✅ | ❌ |
| Persistent case memory | ✅ | ❌ |

**NemoClaw note**: NemoClaw provides the same OpenShell sandbox enforcement — this is where the stacks are most similar. However, on macOS (the most common dev environment), NemoClaw's local inference is broken (DNS bug, issue #260), so inference is routed to cloud APIs (OpenAI, Anthropic, NVIDIA NIM). For HIPAA/legal privilege workloads where data cannot leave the network, **cloud inference routing is disqualifying**. HermesClaw with local llama.cpp on any OS is the viable choice for true air-gapped deployments. On Linux, both stacks can use local models with full OpenShell enforcement.
