data "aws_ami" "my_ami" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

data "aws_iam_instance_profile" "my_ssm_profile" {
  name = "EC2-SSM-Role-devops"
}

module "node1" {
  source                 = "terraform-aws-modules/ec2-instance/aws"
  version                = "~> 6.0"
  name                   = "node1"
  ami                    = data.aws_ami.my_ami.id
  instance_type          = "t3.micro"
  subnet_id              = module.my_vpc.public_subnets[0]
  create_security_group  = false
  vpc_security_group_ids = [module.my_sg.id]
  key_name               = "afiq"
  tags                   = { Name = "node1" }
  iam_instance_profile   = data.aws_iam_instance_profile.my_ssm_profile.name
  root_block_device = { size =16 }
}

module "node2" {
  source                 = "terraform-aws-modules/ec2-instance/aws"
  version                = "~> 6.0"
  name                   = "node2"
  ami                    = data.aws_ami.my_ami.id
  instance_type          = "t3.micro"
  subnet_id              = module.my_vpc.public_subnets[0]
  create_security_group  = false
  vpc_security_group_ids = [module.my_sg.id]
  key_name               = "afiq"
  tags                   = { Name = "node2" }
  iam_instance_profile   = data.aws_iam_instance_profile.my_ssm_profile.name
  root_block_device = { size =16 }
}