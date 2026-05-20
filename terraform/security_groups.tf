resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Public ALB - only ingress on HTTP 80"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.alb_ingress_cidr
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "All egress (to targets inside VPC)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "api" {
  name        = "${local.name_prefix}-api-sg"
  description = "API EC2 - iii engine + caller-worker"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-api-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "api_http_from_alb" {
  security_group_id            = aws_security_group.api.id
  description                  = "HTTP API from ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.engine_http_port
  to_port                      = var.engine_http_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "api_worker_from_infer" {
  security_group_id            = aws_security_group.api.id
  description                  = "iii WorkerManager from Python inference worker"
  ip_protocol                  = "tcp"
  from_port                    = var.engine_worker_port
  to_port                      = var.engine_worker_port
  referenced_security_group_id = aws_security_group.infer.id
}

resource "aws_vpc_security_group_ingress_rule" "api_ssh_admin" {
  count             = var.ssh_key_name == "" ? 0 : 1
  security_group_id = aws_security_group.api.id
  description       = "SSH admin"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.admin_ssh_cidr
}

resource "aws_vpc_security_group_egress_rule" "api_all" {
  security_group_id = aws_security_group.api.id
  description       = "All egress (model pulls, npm, etc.)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "infer" {
  name        = "${local.name_prefix}-infer-sg"
  description = "Python inference EC2 - private subnet"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-infer-sg" }
}

resource "aws_vpc_security_group_egress_rule" "infer_all" {
  security_group_id = aws_security_group.infer.id
  description       = "All egress: HuggingFace via NAT + WS to API EC2"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
