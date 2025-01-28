provider "aws" {
    region = "eu-west-2"
}

resource "aws_instance" "example" {
    ami                    = "ami-0fb653ca2d320ac1" #change before deploying as this is set in a different region
    instance_type          = "t2.micro"
    vpc_security_group_ids = [aws_security_group.instance.id] 

    user_data = <<-EOF
                #!/bin/bash
                echo "Hello, World" > index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF

    user_data_replace_on_change = true
    # User data only runs on the first boot. Terraform works by updating instances so if this was false,
    # you would miss out on the user data

    tags = {
        Name = "terraform-example"
    }
}

resource "aws_security_group" "instance" {
    name = "terraform-example-instance"

    ingress {
        from_port   = var.server_port
        to_port     = var.server_port
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

variable "server_port" {
    description = "The port the server will use for HTTP requests"
    type        = number
    default     = 8080
}

###################################################################################################
# Another way to do it:


resource "aws_launch_configuration" "example" {
    image_id        = "ami-hu68ds88ch"
    instance_type   = "t2.micro"
    security_groups = [aws_security_group.instance.id]

    user_data = <<-EOF
                #!/bin/bash
                echo "Hello, World" > index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF

    # Required when using a launch configuration with an auto-scaling group:
    lifecycle {
        create_before_destroy = true # Solves a problem explained on pg 68
    }
}

resource "aws_autoscaling_group" "example" {
    launch_configuration = aws_launch_configuration.example.name

    min_size = 2
    max_size = 10

    tag {
        key                 = "Name"
        value               = "terraform-asg-example"
        propagate_at_launch = true
    }
}


# Creating a data source:
data "aws_vpc" "default" {
    default = true
}

# Using the data source to look up subnets within VPC:
data "aws_subnets" "default" {
    filter {
        name   = "vpc-id"
        values = [data.aws_vpc.default.id]
    }
}

# Pulling the subnet IDs from the data source and telling the ASG to use them:
resource "aws_autoscaling_group" "example" {
    launch_configuration = aws_launch_configuration.example.name
    vpc_zone_identifier  = data.aws_subnets.default.IDs

    target_group_arns = [aws_lb_target_group.asg.arn]
    health_check_type = "ELB"
    
    min_size = 2
    max_size = 10

    tag {
        key                 = "Name"
        value               = "terraform-asg-example"
        propagate_at_launch = true
    }
}

resource "aws_lb" "example" {
    name               = "terraform-asg-example"
    load_balancer_type = "application"
    subnets            = data.aws_subnets.default.ids
    security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.example.arn
    port              = 80
    protocol          = "HTTP"

    # By default, return a simple 404 page. Default action is required for when the listener receives
    # requests that don't match any listener rules
    default_action {
        type = "fixed-response"

        fixed_response {
            content_type = "text/plain"
            message_body = "404: page not found"
            status_code  = 404
        }
    }

}

# The ALB requires its own security group just like any other AWS resource. We will set this to allow 
# incoming requests on port 80 so that you can access the LB over HTTP, and allow outgoing requests on all
# ports so that the load balancer can perform health checks:
resource "aws_security_group" "alb" {
    name = "terraform-ecample-alb"

    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_lb_target_group" "asg" {
    name     = "terraform-asg-example"
    port     = var.server_port
    protocol = "HTTP"
    vpc_id   = data.aws_vpc.default.id

    health_check {
        path                = "/"
        protocol            = "HTTP"
        matcher             = "200"
        interval            = 15
        timeout             = 3
        healthy_threshold   = 2
        unhealthy_threshold = 2
    }
}

# The above target group health checks the instances by periodically sending an HTTP request to each instance
# and will consider each healthy if it returns a response that matches the matcher. If an instance is marked 
# as unhealthy, the target group will stop sending traffic to it.


# Listener rule that sends requests that match any path to the target group that contains the ASG
resource "aws_lb_listener_rule" "asg" {
    listener_arn = aws_lb_listener.http.arn
    priority = 100

    condition {
        path_patter {
            values = ["*"]
        }
    }

    action {
        type = "forward"
        target_group_arn = aws_lb_target_group.asg.arn
    }
}

output "alb_dns_name" {
    value = aws_lb.example.dns_name
    description = "The domain name of the load balancer"
}