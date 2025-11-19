variable "instance_name" {
  description = "Value of the EC2 instance's Name tag."
  type        = string
  default     = "pi-server"
}

variable "instance_type" {
  description = "The EC2 instance's type."
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "key pair to connect to ec2"
  type        = string
  default     = "pi-mini-server"
}
