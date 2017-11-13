resource "aws_security_group" "bastion" {
  name = "${var.environment}-${var.name}"
  description = "${var.environment}-${var.name} access from WAN"
  vpc_id = "${var.vpc_id}"

  ingress {
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }
}
