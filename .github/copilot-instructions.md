## Quick orientation for AI coding agents

This repository is a small Terraform configuration that provisions an AWS EC2 instance. Keep guidance short, actionable, and tied to the actual files present.

- Primary terraform config: `ec2-cloudflare/` — contains `main.tf`, `variables.tf`, and `terraform.tf`.
- The repo README is minimal (`README.md`). There are no existing agent instruction files to merge.

## Big picture

- Purpose: simple IaC to create a single EC2 instance. The provider is AWS and an Ubuntu AMI is looked up via `data "aws_ami" "ubuntu"` in `ec2-cloudflare/main.tf`.
- The code uses a hard requirement for Terraform core (`required_version = ">= 1.2"`) and pins the AWS provider to `~> 5.92` in `ec2-cloudflare/terraform.tf`.
- There is no remote state backend configured; state defaults to local file storage.

## Important files and patterns (examples)

- `ec2-cloudflare/main.tf` — defines:
  - `provider "aws" { region = "us-east-1" }`
  - `data "aws_ami" "ubuntu" { ... owners = ["099720109477"] }` (Canonical owner ID used to find Ubuntu images)
  - `resource "aws_instance" "app_server" { ami = data.aws_ami.ubuntu.id, instance_type = var.instance_type, tags = { Name = var.instance_name } }`
- `ec2-cloudflare/variables.tf` — declares `instance_name` and `instance_type` with defaults (`pi-server`, `t2.micro`).
- `ec2-cloudflare/terraform.tf` — Terraform and provider version constraints.

## Developer workflows (concrete commands)

When modifying or testing Terraform code in `ec2-cloudflare/` follow these steps locally (assumes AWS credentials available in environment or `~/.aws/`):

  1. terraform init
  2. terraform fmt   # format
  3. terraform validate
  4. terraform plan -var "instance_type=t3.micro"   # example override
  5. terraform apply -auto-approve

Notes: The repo does not configure a remote state backend — use caution when running `apply` (state will be stored locally unless you add a backend).

## Conventions & expectations for changes

- Keep Terraform idiomatic: run `terraform fmt` and `terraform validate` before proposing changes.
- Use variable overrides or `*.tfvars` files rather than hard-coding values when adding configurable behavior. Example: change the instance type by setting `instance_type` in `variables.tf` or passing `-var`/`*.tfvars`.
- Do not assume Cloudflare integration exists despite the folder name `ec2-cloudflare/`; there is currently no Cloudflare provider code to edit. If you add Cloudflare resources, add provider pinning in `terraform.tf` and document new variables.

## Integration points & external requirements

- AWS credentials: expected to be provided via environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`) or configured AWS CLI profiles.
- Terraform version: follow `required_version` in `ec2-cloudflare/terraform.tf` (>= 1.2). Use `terraform version` to confirm.
- Provider compatibility: aws provider pinned to `~> 5.92`.

## What not to change without developer sign-off

- Don't add remote backends or change provider versions without confirmation; that can affect shared infrastructure state.
- Avoid introducing modules or large refactors unless tasked explicitly; this repo is intentionally small and direct.

## When you need more context

- Ask the maintainer for the intended target environment (single-person lab vs. team-managed account), desired state storage (local vs. remote), and whether Cloudflare resources should be present (folder name hints but no code exists).

---
If you'd like, I can now:
- (A) open a PR adding this file, or
- (B) modify the instructions with additional items you want emphasized (auth, tagging, cost controls).
