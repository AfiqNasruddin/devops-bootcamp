output "rackula_url" {
  value = "http://${aws_instance.rackula.public_ip}:8080"
}

output "ssm_command" {
  value = "aws ssm start-session --target ${aws_instance.rackula.id}"
}