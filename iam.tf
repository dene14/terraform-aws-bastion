# IAM Role for ECS Instances in EC2
resource "aws_iam_role" "bastion" {
  name = "${var.environment}-${var.name}"
  assume_role_policy = "${file("${path.module}/files/InstanceRoleTrust.json")}"
}

data "template_file" "bastion_policy" {
    template = "${file("${path.module}/files/BastionPolicy.json")}"

    vars {
        BUCKET  = "${replace("${var.bucket_uri}", "/^(s3://)([^/]*)(.*)$/", "arn:aws:s3:::$2")}"
        BUCKET_URI  = "${replace("${var.bucket_uri}", "/^(s3://)([^/]*)(.*)$/", "arn:aws:s3:::$2$3*")}"
    }
}

resource "aws_iam_policy" "bastion" {
    name = "${var.environment}-${var.name}"
    description = "Policy for ${var.name} at ${var.environment} environment"
    policy = "${data.template_file.bastion_policy.rendered}"
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerServiceforEC2Role" {
  role = "${aws_iam_role.bastion.id}"
  policy_arn = "${aws_iam_policy.bastion.arn}"
}

resource "aws_iam_instance_profile" "bastion" {
    name = "${var.environment}-${var.name}"
    role = "${aws_iam_role.bastion.name}"
}
