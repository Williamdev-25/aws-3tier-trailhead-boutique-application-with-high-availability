data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}




resource "aws_instance" "server" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type
  availability_zone = var.availability_zone
  vpc_security_group_ids = var.security_groups
  subnet_id = var.subnet_id

  user_data                   = var.user_data
  user_data_replace_on_change = true
  iam_instance_profile        = var.iam_instance_profile
  key_name                    = var.key_name

  tags = {
    Name = "Instance-${var.env}"
  }
}
