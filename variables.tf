variable "environment" {}

variable "name" {
  default = "bastion"
}

variable "instance_type" {
  default = "t2.nano"
}

variable "bucket_uri" {}

variable "update_frequency" {
  default = "*/15 * * * *"
}

variable "ami" {
  default = "ami-8fcee4e5"
}

variable "vpc_id" {}

variable "subnet_id" {}

variable "tags" {
  type    = map
  default = {}
}
