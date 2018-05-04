provider "aws" {
  region = "eu-west-1"
}

variable "cidr_block" {
  default = "10.3.0.0/16"
}

module "vpc" {
  source = "modules/vpc"

  name = "devternity-max"

  cidr = "${var.cidr_block}"

  private_subnets = [
    "${cidrsubnet(var.cidr_block, 3, 5)}", //10.10.160.0/19
    "${cidrsubnet(var.cidr_block, 3, 6)}", //10.10.192.0/19
    "${cidrsubnet(var.cidr_block, 3, 7)}"  //10.10.224.0/19
  ]

  public_subnets = [
    "${cidrsubnet(var.cidr_block, 5, 0)}", //10.10.0.0/21
    "${cidrsubnet(var.cidr_block, 5, 1)}", //10.10.8.0/21
    "${cidrsubnet(var.cidr_block, 5, 2)}"  //10.10.16.0/21
  ]

  availability_zones = ["${data.aws_availability_zones.zones.names}"]
}

data "aws_availability_zones" "zones" {}

data "aws_ami" "application_instance_ami" {
  most_recent = true
  filter {
    name = "name"
    values = ["application_instance_1-*"]
  }
  filter {
    name = "tag:Version"
    values = ["1.0.0"]
  }
}


resource "aws_security_group" "instance" {
  name        = "instance"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "6"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "6"
    cidr_blocks = ["0.0.0.0/0"]
    security_groups = ["${aws_security_group.elb.id}"]
  }
}

resource "aws_security_group" "elb" {
  name        = "elb"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "6"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}


resource "aws_key_pair" "ssh_key" {
  key_name   = "devternity"
  public_key = "${file("ssh/devternity.pub")}"
}

resource "aws_launch_configuration" "launch_conf" {
  name_prefix   = "devternity-max-"
  image_id      = "${data.aws_ami.application_instance_ami.id}"
  instance_type = "t2.micro"
  security_groups = ["${aws_security_group.instance.id}"]
  key_name = "${aws_key_pair.ssh_key.key_name}"

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_autoscaling_group" "aws_as_group" {
  vpc_zone_identifier = ["${module.vpc.private_subnets}"]
  name                      = "devternity-max-ag"
  max_size                  = 3
  min_size                  = 0
  health_check_grace_period = 60
  health_check_type         = "ELB"
  desired_capacity          = 3
  launch_configuration      = "${aws_launch_configuration.launch_conf.name}"
  load_balancers = ["${aws_elb.elb.name}"]


  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_elb" "elb" {
  name               = "devternity-max-elb"
  #availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

  subnets = ["${module.vpc.public_subnets}"]
  security_groups = ["${aws_security_group.elb.id}"]
  internal = false

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    target              = "HTTP:80/index.html"
    interval            = 10
  }
}


output "elb_address" {
  value = "${aws_elb.elb.dns_name}"
}