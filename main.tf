provider "aws" {
    region = "eu-west-2"
}

resource "aws_instance" "example" {
    ami = "ami-0fb653ca2d320ac1" #change before deploying as this is set in a different region
    instance_type = "t2.micro"
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
        from_port = var.server_port
        to_port = var.server_port
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

variable "server_port" {
    description = "The port the server will use for HTTP requests"
    type = number
    default = 8080
}

###################################################################################################
# Another way to do it:


resource "aws_launch_configuration" "example" {
    image_id = "ami-hu68ds88ch"
    instance_type = "t2.micro"
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
    vpc_zone_identifier = data.aws_subnets.default.IDs
    
    min_size = 2
    max_size = 10

    tag {
        key                 = "Name"
        value               = "terraform-asg-example"
        propagate_at_launch = true
    }
}

