
provider "aws" {
  region = "${var.region}"
}

module "production-state" {
  source = "../../modules"

#   cert = "${var.cert}"
}