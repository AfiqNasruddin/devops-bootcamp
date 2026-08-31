output "server_ip_public" {
  value = module.my_server_public.public_ip
}

output "server_ip_private" {
  value = module.my_server_private.private_ip
}

output "nat_eip" {
  value = try(module.my_vpc.nat_public_ips[0], null)
}

output "ssm_command_public" {
  value = "aws ssm start-session --target ${module.my_server_public.id}"
}

output "ssm_command_private" {
  value = "aws ssm start-session --target ${module.my_server_private.id}"
}