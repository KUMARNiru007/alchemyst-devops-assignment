locals {
  api_user_data = templatefile("${path.module}/user_data/api.sh.tftpl", {
    git_repo_url       = var.git_repo_url
    git_branch         = var.git_branch
    engine_http_port   = var.engine_http_port
    engine_worker_port = var.engine_worker_port
  })

  infer_user_data = templatefile("${path.module}/user_data/infer.sh.tftpl", {
    git_repo_url       = var.git_repo_url
    git_branch         = var.git_branch
    engine_worker_port = var.engine_worker_port
    api_private_ip     = aws_instance.api.private_ip
  })
}

resource "aws_instance" "api" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.api_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.api.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  key_name                    = var.ssh_key_name == "" ? null : var.ssh_key_name
  associate_public_ip_address = true
  user_data                   = local.api_user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size           = 16
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${local.name_prefix}-api-ec2"
    Role = "api"
  }
}

resource "aws_instance" "infer" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.infer_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.infer.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  key_name                    = var.ssh_key_name == "" ? null : var.ssh_key_name
  user_data                   = local.infer_user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size           = var.infer_root_volume_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${local.name_prefix}-infer-ec2"
    Role = "inference"
  }

  depends_on = [aws_instance.api, aws_nat_gateway.main]
}
