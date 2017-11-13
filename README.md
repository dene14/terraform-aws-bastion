# terraform-aws-bastion
Terraform module to configure bastion server


Example below:
```
module "bastion" {
  source = "https://github.com/dene14/terraform-aws-bastion.git"
  name = "bastion"
  environment ="devenv"
  instance_type = "t2.nano"
  bucket_uri = "s3://somebucket/devenv/"
  update_frequency = "*/15 * * * *"
  ami = "ami-8fcee4e5"
  vpc_id = "${module.vpc.vpc.id}"
  subnet_id = "${element(module.vpc.subnets.public_ids, 0)}"
}

resource "aws_eip" "bastion" {
    vpc = true
}

resource "aws_eip_association" "bastion" {
  instance_id = "${module.bastion.instance.id}"
  allocation_id = "${aws_eip.bastion.id}"
}

resource "aws_route53_record" "service" {
  zone_id = "${var.route53_primary_zone_id}"
  name = "${var.environment}-${module.bastion.name}"
  type = "A"
  ttl = "300"
  records = ["${aws_eip.bastion.public_ip}"]
}
```
