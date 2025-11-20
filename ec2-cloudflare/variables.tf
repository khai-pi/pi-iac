variable "instance_name" {
  description = "Value of the EC2 instance's Name tag."
  type        = string
  default     = "pi-mini-server"
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

variable "cloudflare_zone_domain" {
  description = "Cloudflare domain name (e.g., example.com)"
  type        = string
  default     = "ksea.uk"
}

variable "cloudflare_subdomain" {
  description = "Cloudflare subdomain name (e.g., n8n)"
  type        = string
  default     = "pi-mini-server"
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}
