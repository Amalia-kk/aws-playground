variable "db_username" {
    description = "The username for the database"
    type        = string
    sensitive   = true
}

variable "db_password" {
    description = "The password for the database"
    type        = string
    sensitive   = true
}

# To set the username and password, you can run the following commands:
# export TF_VAR_db_username="username" and
# export TF_VAR_db_password="password"