data "aws_subnet" "bastion" {
  id = "${var.subnet_id}"
}

data "aws_availability_zone" "bastion" {
  name = "${data.aws_subnet.bastion.availability_zone}"
}

data "aws_region" "current" {
  current = true
}
