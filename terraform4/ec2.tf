resource "aws_iam_role" "ec2_ssm_role" {
  name = "tf-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy_attachment" "ssm_attachment" {
  name       = "tf-SSM-Policy-Attachment"
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  roles      = [aws_iam_role.ec2_ssm_role.name]
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "tf-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

data "aws_ami" "my_ami" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "rackula" {
  ami                    = data.aws_ami.my_ami.id
  instance_type          = "t3.micro"
  subnet_id              = module.my_vpc.public_subnets[0]
  vpc_security_group_ids = [module.my_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = templatefile("userdata.sh", {
    rackula_image = "ghcr.io/rackulalives/rackula:latest"
    rackula_port  = "8080"
  })

  tags = { Name = "tf-rackula-instance" }
}