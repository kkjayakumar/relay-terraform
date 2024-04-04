variable "AWS_REGION" {
  default = "us-east-1"
}

variable "AMIS" {
  type = map(string)
  default = {
    "us-east-1" = "ami-080e1f13689e07408"
  }
}

# variable "PATH_TO_PRIVATE_KEY" {
#   default = "mykeyy"
# }

# variable "PATH_TO_PUBLIC_KEY" {
#   default = "mykeyy.pub"
# }

variable "INSTANCE_USERNAME" {
  default = "ubuntu"
}