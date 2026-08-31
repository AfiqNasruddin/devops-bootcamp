# Terraform v4: Rackula on AWS

Infrastructure as code for deploying Rackula (rack layout designer) on AWS using Terraform.

## Architecture

- **VPC**: `10.20.0.0/16` with one public subnet in `ap-southeast-1a`
- **Subnet**: Public `10.20.1.0/24` with auto-assign IP on launch
- **Security Group**: Allows inbound TCP port **8080** (Rackula web UI) from anywhere
- **EC2 Instance**: t3.micro running Ubuntu 24.04 with:
  - Docker installed via `curl -fsSL https://get.docker.com | sh`
  - Rackula running via Docker Compose on port 8080
  - SSM managed instance profile for browser-based session access

## Ports Used

| Service | Port |
|---|---|
| Rackula Web UI | 8080 (host -> container) |
| Rackula API | 3001 (internal only, not exposed) |

## Outputs

| Output | Value |
|---|---|
| `rackula_url` | `http://<public_ip>:8080` |
| `ssm_command` | `aws ssm start-session --target <instance_id>` |

## Prerequisites

- AWS credentials configured (environment variables, shared credentials file, or IAM role)
- Terraform >= 1.15

## Usage

```bash
terraform init
terraform apply
```

After apply, access Rackula at the printed URL and use the SSM command for session access.

## Files

| File | Description |
|---|---|
| `providers.tf` | AWS provider configuration (v6.62.0) |
| `network.tf` | VPC and public subnet module |
| `security.tf` | Security group allowing port 8080 |
| `ec2.tf` | EC2 instance with Docker, Rackula compose, SSM policy |
| `userdata.sh` | Bootstrap script: installs Docker, creates compose file, starts Rackula |
| `outputs.tf` | URL and SSM command outputs |