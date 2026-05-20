# Distributed Inferencing on AWS — `iii` Quickstart

Production-style deployment of the [`iii`](https://iii.dev) cross-language
worker mesh from the
[DevOps internship assignment](../devops-internship-assignment.md). A small
language model (`gemma-3-270m`, GGUF Q8) runs on a private VM and is reached
through a TypeScript worker over an `iii` RPC, fronted by a public AWS
Application Load Balancer that speaks plain JSON HTTP.

The whole stack is reproducible from this repository: one `terraform apply`
provisions the VPC, both worker VMs, the load balancer, IAM, and brings the
services up as `systemd` units that survive reboots.

---

## Live test

```bash
curl -X POST "http://iii-alb-393598203.ap-south-1.elb.amazonaws.com/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"hi"}]}'
```

Sample response (truncated):

```json
{
  "result": {
    "0": "h", "1": "i", "2": "-", "3": "d", "4": "i", "...": "...",
    "success": "You've connected two workers and they're interoperating seamlessly, now let's add a few more workers to expand this project's functionality."
  }
}
```

> The `"0":"h","1":"i",...` shape is a known quirk: the Python worker returns a
> string and the TypeScript caller spreads it before returning, which turns each
> character into a numbered key. The end-to-end RPC + JSON path is what the
> assignment evaluates; fixing the shape is a one-line change in `caller-worker`
> noted under *Known limitations*.

---

## Architecture

```text
                          Internet
                              |
                           HTTP :80
                              |
                  +-----------v-----------+
                  |  ALB  (iii-alb)       |   SG: iii-alb-sg
                  |  Public subnets x 2   |     :80 from 0.0.0.0/0
                  +-----------+-----------+
                              |
                       HTTP :3111
                              |
+-----------------------------v-----------------------------+
|  API EC2  (iii-api-ec2)          Public subnet            |
|  -------                                                  |
|  systemd: iii-engine     -> iii engine (orchestrator)     |
|  systemd: iii-caller     -> caller-worker (TypeScript)    |
|                                                           |   SG: iii-api-sg
|  Listens on :3111 (HTTP API), :49134 (worker manager WS)  |     :3111 from iii-alb-sg
+-----------------------------+-----------------------------+     :49134 from iii-infer-sg
                              |
                      WebSocket :49134
                              |
+-----------------------------v-----------------------------+
|  Inference EC2  (iii-infer-ec2)  Private subnet           |
|  -------                                                  |
|  systemd: iii-inference  -> Python inference-worker       |   SG: iii-infer-sg
|  Loads gemma-3-270m (GGUF, Q8) via transformers           |     no public ingress
|  Registers function `inference::run_inference`            |
+-----------------------------+-----------------------------+
                              |
                       Outbound only
                              |
                       +------v------+
                       |  NAT GW     |   for HuggingFace model download
                       +-------------+
                              |
                          Internet
```

Request flow:

1. Client `POST /v1/chat/completions` to ALB.
2. ALB forwards to API EC2 `:3111`.
3. `iii-http` trigger dispatches to `http::run_inference_over_http`
   (TypeScript).
4. Caller-worker invokes `inference::get_response` -> `inference::run_inference`
   over WebSocket to the engine.
5. Engine forwards the call to the Python inference-worker on the private
   inference EC2.
6. Python decodes with `transformers`, returns the string. Caller-worker wraps
   it, engine returns JSON to ALB to client.

---

## Repository layout

```text
quickstart/
├── README.md                       <- you are here
├── config.yaml                     <- iii engine config (HTTP, queue, state)
├── body.json                       <- sample request body for curl tests
├── iii.worker.yaml                 <- engine project manifest
├── workers/
│   ├── caller-worker/              <- TypeScript: HTTP -> RPC
│   │   ├── src/worker.ts
│   │   ├── iii.worker.yaml
│   │   └── package.json
│   └── inference-worker/           <- Python: model + RPC handler
│       ├── inference_worker.py
│       ├── iii.worker.yaml
│       └── requirements.txt
└── terraform/                      <- Infrastructure as code (see below)
    ├── README.md
    ├── *.tf
    └── user_data/
        ├── api.sh.tftpl
        └── infer.sh.tftpl
```

---

## Deploy with Terraform (recommended)

### Prerequisites

- AWS account with credentials configured (`aws configure` or env vars).
- Terraform >= 1.5.
- ~5 minutes for resources, plus ~10 minutes inside the VMs for
  `apt-get` / `npm install` / `pip install` / first model download.

### Apply

```bash
git clone https://github.com/KUMARNiru007/alchemyst-devops-assignment.git
cd alchemyst-devops-assignment/terraform

cp terraform.tfvars.example terraform.tfvars   # tweak if needed
terraform init
terraform apply -auto-approve
```

Outputs include the public URL:

```text
api_url      = "http://iii-alb-xxxxxxxx.ap-south-1.elb.amazonaws.com/v1/chat/completions"
sample_curl  = "curl -X POST http://... -H 'Content-Type: application/json' -d '...'"
```

### Test

```bash
curl -X POST "$(terraform output -raw api_url)" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"hi"}]}'
```

The **first** request after `apply` can take 1–3 minutes because the inference
EC2 has to download `gemma-3-270m-Q8_0.gguf` (~270 MB) from HuggingFace.
Subsequent requests are seconds.

### Destroy

```bash
terraform destroy -auto-approve
```

Tears down everything: ALB, EC2s, NAT, EIP, subnets, SGs, IAM. No orphan
resources left behind.

See `terraform/README.md` for a full description of the resources and
variables.

---

## What changed vs the upstream `quickstart` template

The upstream template is designed for **local** development with `iii`
sandboxing all workers in micro-VMs on a developer laptop. To run it as a
real distributed system on AWS, the following changes were made — all
captured in git history and reproduced automatically by Terraform.

| # | File | Change | Why |
|---|------|--------|-----|
| 1 | `config.yaml` | Removed `inference-worker` and `caller-worker` `worker_path` entries | Workers now run as **external processes** on their own VMs, not as sandboxed children of the engine. The engine only manages its own built-ins. |
| 2 | `config.yaml` | `iii-http.host`: `127.0.0.1` -> `0.0.0.0` | The ALB target group connects to the EC2's **private IP**, not loopback. Loopback would make the target permanently unhealthy. |
| 3 | `config.yaml` | `default_timeout`: `30000` -> `300000` | First inference on CPU (t3.medium) can take 30+ seconds; the engine was killing slow RPC calls before the model could respond. |
| 4 | `workers/inference-worker/inference_worker.py` | `InitOptions(worker_name="math-worker")` -> `"inference-worker"` | Match the worker's real role. The original template was a leftover from the math example. |
| 5 | `workers/inference-worker/inference_worker.py` | `model.generate(..., max_new_tokens=32000)` -> `64` | 32k tokens on CPU is multiple minutes per request. 64 tokens is plenty for a demo and finishes well inside any sensible HTTP timeout. |
| 6 | `terraform/` | New | Provisions every resource so the system is reproducible on a clean AWS account. |

Other observations during integration that did **not** require code changes:

- `caller-worker` still uses `ws://localhost:49134` because it runs on the
  **same** VM as the engine; only the Python worker needs to dial the
  engine across the VPC. The Python worker reads `III_URL` from the
  environment, which the `iii-inference.service` systemd unit sets to
  `ws://<api_private_ip>:49134`.
- The engine binds **both** `:3111` (HTTP) and `:49134` (worker manager)
  on `0.0.0.0` automatically. Only `:3111` is controlled by `iii-http.host`
  in `config.yaml`; `:49134` follows the same all-interfaces behaviour as
  long as the engine isn't pinned to loopback.

---

## Manual deployment (alternative path)

Useful for understanding or debugging the same setup without Terraform.

### 1. API EC2 (public subnet)

Provision an Ubuntu 24.04 t3.small in a public subnet with `iii-api-sg`
attached, then:

```bash
# 1. Install prerequisites
sudo apt-get update -y
sudo apt-get install -y git jq tmux curl
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt-get install -y nodejs

# 2. Install the iii engine
curl -fsSL https://iii.dev/install.sh | bash

# 3. Get the project
git clone https://github.com/KUMARNiru007/alchemyst-devops-assignment.git ~/quickstart
cd ~/quickstart

# 4. Start the engine and caller in tmux (or use systemd units from terraform/)
tmux new-session -d -s iii -n engine
tmux send-keys -t iii:engine 'iii --config config.yaml' C-m
tmux new-window -t iii -n caller
tmux send-keys -t iii:caller 'cd workers/caller-worker && npm install && npx tsx watch src/worker.ts' C-m
```

### 2. Inference EC2 (private subnet)

Provision an Ubuntu 24.04 t3.medium in a private subnet (route to NAT
Gateway) with `iii-infer-sg` attached, reach it via SSM Session Manager:

```bash
sudo apt-get update -y
sudo apt-get install -y git python3-venv python3-pip tmux

git clone https://github.com/KUMARNiru007/alchemyst-devops-assignment.git ~/quickstart
cd ~/quickstart/workers/inference-worker
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

tmux new -s infer
export III_URL="ws://<api-private-ip>:49134"
.venv/bin/python inference_worker.py
```

### 3. Security groups

| Group | Inbound | Outbound |
|-------|---------|----------|
| `iii-alb-sg` | TCP 80 from 0.0.0.0/0 | All |
| `iii-api-sg` | TCP 3111 from `iii-alb-sg`, TCP 49134 from `iii-infer-sg` (optional SSH 22 from your /32) | All |
| `iii-infer-sg` | none | All (needs NAT for HuggingFace, and VPC for `:49134`) |

---

## Operations and debugging

When deployed via Terraform both VMs are reachable through SSM (no SSH
key required):

```bash
# API EC2
aws ssm start-session --target $(terraform -chdir=terraform output -raw api_instance_id)
sudo journalctl -u iii-engine -f
sudo journalctl -u iii-caller -f

# Inference EC2 (private)
aws ssm start-session --target $(terraform -chdir=terraform output -raw infer_instance_id)
sudo journalctl -u iii-inference -f
```

Quick health checks:

```bash
# On API EC2 (engine should answer 404 on `/`)
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:3111/

# Listening ports
ss -ltnp | grep -E '3111|49134'

# Process state
systemctl status iii-engine iii-caller
systemctl status iii-inference   # on the inference VM
```

---

## Destroy and re-deploy: what to expect

Yes, the system is fully reproducible. Running `terraform destroy` followed
by `terraform apply` rebuilds an identical stack. A few things **change by
design**:

| Item | Stable across re-deploys? | Notes |
|------|---------------------------|-------|
| VPC CIDR (`10.0.0.0/16`) | Yes | Set in `variables.tf`. |
| Security group rules and names | Yes | Same names, same rules. |
| IAM role / instance profile names | Yes | Hardcoded. |
| ALB DNS name | **No** | AWS generates a new DNS for each new ALB. **You will need to update the curl URL in your demo / README after re-deploy** — `terraform output api_url` always gives the current one. |
| EC2 private IPs | **No** | New IPs each time. The infer EC2's `III_URL` is rendered with the **current** API private IP at apply time, so it self-heals. |
| Model on disk | **No** | The 270 MB GGUF is downloaded again from HuggingFace on first request. Allow ~2 minutes for the first inference. |
| Engine and caller startup | Yes | `systemd` brings them up automatically; no manual `tmux` needed. |
| Worker registration | Yes | `inference-worker` self-registers via `register_worker(III_URL, ...)`. |

**No extra manual steps are required after a clean re-deploy.** Just run
the curl from `terraform output sample_curl` once user-data finishes
(~10 minutes for the first apply, less on subsequent ones if the EC2 is
recycled and only systemd services need to start). You can watch progress
with `sudo tail -f /var/log/cloud-init-output.log` on either instance over
SSM.

---

## Known limitations

These are deliberately left for the production-hardening write-up rather
than fixed inline.

- **Response JSON shape.** The Python worker returns a string and the
  TypeScript caller spreads it (`return { ...result, success: ... }`),
  producing `{"0":"h","1":"i",...}`. Replacing the spread with
  `{ text: result, success: ... }` in `workers/caller-worker/src/worker.ts`
  cleans this up.
- **No HTTPS.** ALB listens on plain HTTP/80. Add an ACM cert and a 443
  listener for production.
- **No auto-scaling on the API tier.** The engine holds the WorkerManager
  WebSocket; adding a second API instance would let workers register on
  only one of them. Externalising the WorkerManager (or running a
  per-instance engine with sticky workers) is the path forward.
- **One NAT Gateway, not one per AZ.** Cost-optimised for a demo.
- **SSH key is opt-in.** Default deploy has `ssh_key_name = ""` so the only
  admin path is SSM. Set the variable in `terraform.tfvars` to enable SSH.
- **Inference is CPU.** Fine for `gemma-3-270m`; replace with a GPU
  instance family + a model server (vLLM, TGI) for anything larger. See
  notes in `WRITEUP.md` (if present).

---

## Submission details

- Repository: <https://github.com/KUMARNiru007/alchemyst-devops-assignment>
- Live endpoint (current deploy):
  `http://iii-alb-393598203.ap-south-1.elb.amazonaws.com/v1/chat/completions`
- Region: `ap-south-1`
- Reproduce on a clean account: see *Deploy with Terraform* above.
