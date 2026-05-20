output "alb_dns_name" {
  description = "Public DNS of the ALB. Hit this to reach the JSON API."
  value       = aws_lb.main.dns_name
}

output "api_url" {
  description = "Full curl-able URL for inference."
  value       = "http://${aws_lb.main.dns_name}/v1/chat/completions"
}

output "api_instance_id" {
  description = "EC2 instance ID for the API/engine VM (for SSM Session Manager)."
  value       = aws_instance.api.id
}

output "api_public_ip" {
  description = "Public IPv4 of the API EC2 (for SSH debug if ssh_key_name is set)."
  value       = aws_instance.api.public_ip
}

output "api_private_ip" {
  description = "Private IPv4 of the API EC2 (engine WS endpoint inside the VPC)."
  value       = aws_instance.api.private_ip
}

output "infer_instance_id" {
  description = "EC2 instance ID for the Python inference VM (private subnet, SSM only)."
  value       = aws_instance.infer.id
}

output "infer_private_ip" {
  description = "Private IPv4 of the inference EC2 (no public IP)."
  value       = aws_instance.infer.private_ip
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "sample_curl" {
  description = "Copy this into a terminal to test the deployed API."
  value       = "curl -X POST http://${aws_lb.main.dns_name}/v1/chat/completions -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'"
}
