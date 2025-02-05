provider "aws" {
    region = "eu-west-2"
}

resource "aws_db_instance" "example" {
    identifier_prefix   = "terraform-up-and-running"
    engine              = "mysql"
    allocated_storage   = 10                         # GB
    instance_class      = "db.t2.micro"
    skip_final_snapshot = true
    db_name             = "example_database"

    # Must have a username and password but we don't want to specify secrets here
    # One option is to store them outside of terraform, e.g. 1password, and pass them in via environment 
    # variables
    username            = var.db_username
    password            = var.db_password
}

# Page 108 it asks you to update your terraform.tfstate which we can't do yet because we haven't initialised
# terraform yet