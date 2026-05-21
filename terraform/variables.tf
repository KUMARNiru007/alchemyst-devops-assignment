variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used on every resource name and tag."
  type        = string
  default     = "iii"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). ALB + API EC2."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Inference EC2."
  type        = list(string)
  default     = ["10.0.128.0/20", "10.0.144.0/20"]
}

variable "api_instance_type" {
  description = "Instance type for the API (TS caller + iii engine) EC2."
  type        = string
  default     = "t3.small"
}

variable "infer_instance_type" {
  description = "Instance type for the Python inference EC2. CPU-only is fine for gemma-3-270m."
  type        = string
  default     = "m7i-flex.large"
}

variable "infer_root_volume_gb" {
  description = "Root EBS size for the inference EC2 (model + venv ~ 2-3 GB)."
  type        = number
  default     = 20
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name for SSH into the API EC2. Leave empty to disable SSH and use SSM only."
  type        = string
  default     = ""
}

variable "admin_ssh_cidr" {
  description = "CIDR allowed to SSH into the API EC2. Use your /32. Ignored if ssh_key_name is empty."
  type        = string
  default     = "0.0.0.0/0"
}

variable "alb_ingress_cidr" {
  description = "CIDR allowed to hit the public ALB on port 80."
  type        = string
  default     = "0.0.0.0/0"
}

variable "git_repo_url" {
  description = "Git repository to clone on both EC2s (must contain the quickstart project at the root)."
  type        = string
  default     = "https://github.com/KUMARNiru007/alchemyst-devops-assignment.git"
}

variable "git_branch" {
  description = "Branch to check out."
  type        = string
  default     = "main"
}

variable "engine_http_port" {
  description = "Port the iii HTTP API listens on (must match config.yaml iii-http.port)."
  type        = number
  default     = 3111
}

variable "engine_worker_port" {
  description = "Port the iii WorkerManager listens on (default 49134)."
  type        = number
  default     = 49134
}
