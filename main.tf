provider "aws" {
    region = "eu-west-2"
}

resource "aws_instance" "example" {
    ami = "ami-0fb653ca2d320ac1" #change before deploying as this is set in a different region
    instance_type = "t2.micro"

    tags = {
        Name = "terraform-example"
    }
}

