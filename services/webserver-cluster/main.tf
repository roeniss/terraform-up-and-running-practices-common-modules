terraform {
  required_version = "1.4.0"
 
  backend "s3" {
    bucket         = "terraform-up-and-running-state-jkhqwef"
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-up-and-running-locks-jkhqwef"
    encrypt        = true
  }
}

# provider "aws" {
#   region = "us-east-2"
# }

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "terraform_remote_state" "db" { 
	backend = "s3"

	config = {
		bucket = var.db_remote_state_bucket # "terraform-up-and-running-state-jkhqwef"
		key = var.db_remote_state_key # "stage/data-stores/mysql/terraform.tfstate"
		region = "us-east-2"
	}
}

locals {
  http_port = 80
  any_port = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips = ["0.0.0.0/0"]
}

data "template_file" "user_data" {
  template = file("${path.module}/user_data.sh")

  vars = {
    server_port = var.server_port
    db_address = data.terraform_remote_state.db.outputs.address
    db_port    = data.terraform_remote_state.db.outputs.port
  }
}

resource "aws_launch_configuration" "default" {
  image_id        = "ami-00eeedc4036573771"
  instance_type   = var.instance_type
  security_groups = [aws_security_group.asg.id]

  user_data = data.template_file.user_data.rendered

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "default" {
  launch_configuration = aws_launch_configuration.default.id
  vpc_zone_identifier  = data.aws_subnet_ids.default.ids

  target_group_arns = [aws_lb_target_group.default.arn]
  health_check_type = "ELB"

  min_size = var.min_size
  max_size = var.max_size

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-asg-default"
    propagate_at_launch = true
  }

}


resource "aws_lb" "default" { # albs
  name               = "${var.cluster_name}-lb"
  load_balancer_type = "application"
  subnets            = data.aws_subnet_ids.default.ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  port              = local.http_port
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "default" {
  listener_arn = aws_lb_listener.default.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
}

resource "aws_lb_target_group" "default" {
  name     = "${var.cluster_name}-lb-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-lb-sg"
}

resource "aws_security_group_rule" "lb_allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.any_port
  to_port     = local.any_port
  protocol    = local.any_protocol
  cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "lb_allow_http_outbound" {
  type = "egress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.any_port
  to_port     = local.any_port
  protocol    = local.any_protocol
  cidr_blocks = local.all_ips
}

resource "aws_security_group" "asg" {
  name = "${var.cluster_name}-asg-sg"

}

resource "aws_security_group_rule" "asg_allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.asg.id

  from_port   = var.server_port
  to_port     = var.server_port
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}
