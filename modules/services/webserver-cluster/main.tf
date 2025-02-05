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
    name            = "${var.cluster_name}-instance"   # Previously was "terraform-example-instance"

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
    instance_type   = var.instance_type
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

# Alternative example using the user-data script:
# resource "aws_launch_configuration" "example" {
    # image_id                = "am-12345"
    # instance_type           = var.instance_type
    # security_groups         = [aws_security_group.instance.id]
# 
    # user_data = templatefile("${path.module}/user-data.sh", {
        # server_port         = var.server_port
        # db_address          = data.terraform_remote_state.db.outputs.address
        # db_port             = data.terraform_remote_state.db.outputs.port
    # })
# 
    # lifecycle {
    #   create_before_destroy = true
    # }
# }

resource "aws_autoscaling_group" "example" {
    launch_configuration = aws_launch_configuration.example.name

    min_size = var.min_size
    max_size = var.max_size

    tag {
        key                 = "Name"
        value               = var.cluster_name
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
resource "aws_autoscaling_group" "example2" {
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

locals {
    http_port    = 80
    any_port     = 0
    any_protocol = "-1"
    tcp_protocol = "tcp"
    all_ips      = ["0.0.0.0/0"]
}

resource "aws_lb_listener" "http" {
    load_balancer_arn    = aws_lb.example.arn
    port                 = local.http_port
    protocol             = "HTTP"

    # By default, return a simple 404 page. Default action is required for when the listener receives
    # requests that don't match any listener rules
    default_action {
        type             = "fixed-response"

        fixed_response {
            content_type = "text/plain"
            message_body = "404: page not found"
            status_code  = 404
        }
    }

}

# The ALB requires its own security group just like any other AWS resource. This will allow incoming requests
# on port 80 so that you can access the LB over HTTP, and allow outgoing requests on all ports so that the
# LB can perform health checks:
resource "aws_security_group" "alb" {
    name = "${var.cluster_name}-alb"

    ingress {
        from_port   = local.http_port
        to_port     = local.http_port
        protocol    = local.tcp_protocol # Transmission Control Protocol): communication between devices
        cidr_blocks = local.all_ips
    }

    egress {
        from_port   = local.any_port
        to_port     = local.any_port
        protocol    = local.any_protocol
        cidr_blocks = local.all_ips
    }
}

#########################################################################################################

# Another option for the above would be to write it out in separate blocks. In the above, a user of the
# module would have no way of adding more ingress or egress rukes from outside the module

resource "aws_security_group" "alb" {
    name = "${var.cluster_name}-alb"
}

resource "aws_security_group_rule" "allow_http_inbound" {
    type = "ingress"
    security_group_id = aws_security_group.alb.id

    from_port = local.http_port
    to_port = local.http_port
    protocol = local.tcp_protocol
    cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound" {
    type = "egress"
    security_group_id = aws_security_group.alb.id

    from_port = local.any_port
    to_port = local.any_port
    protocol = local.any_protocol
    cidr_blocks = local.all_ips
}



#########################################################################################################
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
        path_pattern {
            values = ["*"]
        }
    }

    action {
        type = "forward"
        target_group_arn = aws_lb_target_group.asg.arn
    }
}


# Storage:

resource "aws_s3_bucket" "terraform_state" {
    bucket = "amalia-staging-bucket"  # This needs to be unique

    # Prevent accidental deletion of this S3 bucket
    lifecycle {
        prevent_destroy = true
    }
}

resource "aws_s3_bucket_versioning" "enabled" {
    bucket     = aws_s3_bucket.terraform_state.id

    versioning_configuration {
        status = "enabled"
    }
}

resource "aws_server_side_encryption_configuration" "default" {
    bucket                = aws_s3_bucket.terraform_state.id

    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
    bucket                  = aws_s3_bucket.terraform_state.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {     # Used for locking
    name         = "staging-locks"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "LOCK_ID"

    attribute {
        name     = "LockID"
        type     = "S"
    }
}

terraform {
    backend "s3" {
        bucket         = "amalia-staging-bucket"
        key            = "stage/services/webserver-cluster/terraform.tfstate"     # Where the state file should be written
        region         = "eu-west-2"

        dynamodb_table = "staging-locks"  
        encrypt        = true
    }
}

data "terraform_remote_state" "db" {
    backend    = "s3"

    config = {
        bucket = var.db_remote_state_bucket
        key    = var.db_remote_state_key
        region = "eu-west-2"
    }
}