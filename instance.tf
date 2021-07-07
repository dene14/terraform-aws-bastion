data "template_file" "user_data" {
  template = "${file("${path.module}/files/bastion_init.sh")}"

  vars = {
    UPDATE_FREQUENCY = "${var.update_frequency}"
    REGION           = "${data.aws_region.current.name}"
    BUCKET           = "${replace("${var.bucket_uri}", "/^(s3://)([^/]*)(.*)$/", "$2")}"
    BUCKET_PREFIX    = "${replace("${var.bucket_uri}", "/^(s3://)([^/]*)(.*)$/", "$3")}"
  }
}

resource "aws_instance" "bastion" {
  ami                    = "${var.ami}"
  instance_type          = "${var.instance_type}"
  subnet_id              = "${var.subnet_id}"
  iam_instance_profile   = "${aws_iam_instance_profile.bastion.name}"
  vpc_security_group_ids = ["${aws_security_group.bastion.id}"]
  user_data              = "${data.template_file.user_data.rendered}"
  tags                   = "${merge(map("Name", "${var.environment}-${var.name}"),"${var.tags}")}"

  # Any metadata changes will trigger instance destroy
  # see: https://github.com/terraform-providers/terraform-provider-aws/issues/23
  lifecycle {
    ignore_changes = [user_data]
  }
}
