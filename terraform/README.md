# Terraform — distributed iii inference on AWS

One-command provisioning for the `quickstart` project. Stands up:

- A VPC with two public + two private subnets across two AZs.
- Internet Gateway + a single NAT Gateway so the private inference VM can pull
  the HuggingFace model.
- An Application Load Balancer (the **only** public entry point).
- An **API EC2** (public subnet) running the `iii` engine and the TypeScript
  `caller-worker` as systemd services.
- An **inference EC2** (private subnet, no public IP) running the Python
  `inference-worker` as a systemd service, connected to the engine over the
  internal VPC.
- Security groups so:
  - The ALB only accepts HTTP/80 from the internet.
  - The API EC2 only accepts `:3111` from the ALB and `:49134` from the
    inference SG.
  - The inference EC2 has no public ingress at all.
- IAM instance profile with `AmazonSSMManagedInstanceCore` so both VMs are
  reachable over SSM Session Manager without SSH keys.

## Architecture

```text
                    Internet
                       |
                  +----v-----+
                  |   ALB    |   iii-alb-sg : 80 from 0.0.0.0/0
                  +----+-----+
                       |
              HTTP :3111 (alb-sg only)
                       |
        +--------------v---------------+
        |  API EC2 (public subnet)     |
        |  - iii engine                |
        |  - caller-worker (TS)        |   iii-api-sg
        +--------------+---------------+
                       |
            WS :49134 (infer-sg only)
                       |
        +--------------v---------------+
        |  Inference EC2 (private)     |
        |  - inference-worker (Python) |   iii-infer-sg
        |  - gemma-3-270m (GGUF)       |
        +------------------------------+
                       |
                 NAT Gateway
                       |
                  HuggingFace
```

## Prerequisites

- Terraform >= 1.5
- An AWS account and credentials available to Terraform
  (`aws configure` or `AWS_*` env vars).
- The application repo pushed to GitHub. Default points at
  `https://github.com/KUMARNiru007/alchemyst-devops-assignment.git` —
  override `git_repo_url` if you fork it.

## Apply

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # optional, edit if needed
terraform init
terraform apply
```

The first apply takes ~5 min for AWS resources plus a few minutes inside the
VMs for `apt-get`, `npm install`, `pip install` and the first model download
(visible in `/var/log/cloud-init-output.log` on each EC2).

When apply finishes you get:

```text
Outputs:

alb_dns_name      = "iii-alb-xxxxxxxx.ap-south-1.elb.amazonaws.com"
api_url           = "http://iii-alb-xxxxxxxx.ap-south-1.elb.amazonaws.com/v1/chat/completions"
sample_curl       = "curl -X POST ..."
api_instance_id   = "i-..."
infer_instance_id = "i-..."
```

## Test

```bash
curl -X POST "$(terraform output -raw api_url)" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"hi"}]}'
```

The first inference can take 1–2 minutes on a `t3.medium` because the model
is loading for the first time. Subsequent requests are faster.

## Debug

```bash
# API EC2 (engine + caller)
aws ssm start-session --target $(terraform output -raw api_instance_id)
sudo journalctl -u iii-engine -f
sudo journalctl -u iii-caller -f

# Inference EC2 (Python worker, private subnet)
aws ssm start-session --target $(terraform output -raw infer_instance_id)
sudo journalctl -u iii-inference -f
```

The target group health (EC2 → Target Groups → `iii-api-tg`) must be
**healthy** before the ALB will route requests. Health checks expect a
response on `GET /` from the engine — `200-499` is treated as healthy.

## Destroy

```bash
terraform destroy
```

## What's intentionally kept simple

- One NAT Gateway in one AZ to keep cost low. For real production use one
  NAT per AZ.
- No HTTPS on the ALB (no ACM cert). Add a `aws_lb_listener` on port 443
  with `aws_acm_certificate` for production.
- No Auto Scaling Group on the API tier — the engine holds in-memory state
  for the WorkerManager port. For HA, externalize state and put the API
  behind an ASG.
- SSM is the primary admin path; SSH is opt-in via `ssh_key_name`.

## Variables you'll likely tweak

| Variable | Default | Why |
|----------|---------|-----|
| `aws_region` | `ap-south-1` | Match your account. |
| `git_repo_url` / `git_branch` | this repo | If you fork. |
| `api_instance_type` | `t3.small` | Engine + Node + tsx. |
| `infer_instance_type` | `t3.medium` | CPU-only inference; bump for speed. |
| `ssh_key_name` | `""` | Set to existing key pair name to allow SSH. |
| `admin_ssh_cidr` | `0.0.0.0/0` | Restrict to your `x.x.x.x/32`. |
| `alb_ingress_cidr` | `0.0.0.0/0` | Restrict if you want a private demo. |
