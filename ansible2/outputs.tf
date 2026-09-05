output "node1_ip" { value = module.node1.public_ip }
output "node2_ip" { value = module.node2.public_ip }

output "ssm_command_1" {
  value = "aws ssm start-session --target ${module.node1.id}"
}

output "ssm_command_2" {
  value = "aws ssm start-session --target ${module.node2.id}"
}