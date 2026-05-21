# Writeup

This is how I would improve the system if it had to run in real production, and
what I would change if the model were 100x larger. This is written from my
current learning level, so it is more practical than perfect.

## What I would harden before production

- **Tighter security groups.** Right now they are simple and open to make the
  demo work. In production I would restrict ALB ingress to known CIDRs, lock
  down outbound rules, and remove any extra ports.
- **HTTPS/TLS.** I would add an ACM certificate and terminate TLS on the ALB.
  Plain HTTP is fine for the assignment but not for real traffic.
- **WAF in front of the ALB.** This would help block basic bad traffic and
  rate-limit spammy requests.
- **Secrets management.** Any API keys or model tokens should be in AWS
  Secrets Manager or SSM Parameter Store, not hard-coded or passed in plain
  text.
- **Least-privilege IAM.** The EC2 role is very open for a demo. I would trim
  it down to only the actions the instance needs.
- **Monitoring and logs.** I would ship logs to CloudWatch and set up metrics
  and alarms for CPU, memory, disk, and HTTP error rates. Right now logs are
  local only.
- **Health checks and retries.** I would add explicit health endpoints and
  make the caller more resilient with retries for transient RPC failures.
- **CI/CD.** I would build a pipeline to run lint/tests and deploy changes
  with a clear promotion path instead of SSH or manual updates.
- **Better bootstrap reliability.** The `iii` CLI install needs to be pinned
  and verified. I would either bake it into an AMI or use a container image so
  cloud-init is not downloading it every time.
- **Immutable deployments.** I would avoid manual changes on a live instance.
  Build once, deploy cleanly, roll back if needed.
- **Backups and state handling.** I would move Terraform state to an S3 backend
  with locking, and back up any important data stores instead of keeping them
  only on disk.
- **Autoscaling for the API layer.** The HTTP API should be able to scale out
  behind the ALB when traffic grows.
- **Better observability.** Add traces and structured logs so I can tell where
  latency comes from (HTTP vs RPC vs model inference).

## If the model were 100x larger

The current setup is fine for a tiny model. A 100x larger model changes the
whole story because compute, memory, and latency become the main problems.

Here is how I would approach it:

- **Use GPU instances.** CPU-only will not work well at that size. I would move
  the inference layer to GPU instances (or a managed inference service if that
  is allowed).
- **Scale inference separately from API.** The API layer is light and can scale
  horizontally behind the ALB. Inference is heavy, expensive, and harder to
  scale, so it needs its own scaling plan.
- **Multiple inference workers.** Instead of a single inference EC2, I would
  run several workers and load balance requests across them. That could be an
  ASG or a cluster with a scheduler.
- **Batching and caching.** I would batch similar requests and cache repeated
  prompts to reduce GPU load and costs.
- **Async queues.** For slow requests, I would use a queue so the API can reply
  quickly with a job ID and clients can poll or use websockets.
- **Dedicated inference cluster.** At that point I would consider ECS/EKS or
  Kubernetes so I can schedule GPU workloads and roll updates safely.
- **High availability and multi-region.** Large models are expensive to host,
  so I would set up at least multi-AZ, and later multi-region for resiliency.
- **More strict SLOs.** With bigger models, I would define latency and uptime
  targets and monitor them tightly.

Why the scaling difference matters:

- The API layer is stateless and can scale out easily.
- The inference layer is stateful, heavy, and GPU-bound. Scaling it is harder
  and costs more, so it needs careful capacity planning.
- A larger model increases memory usage, latency, throughput requirements, and
  operational complexity. That is why the single-VM inference setup is fine for
  this assignment but not for a 100x model.
