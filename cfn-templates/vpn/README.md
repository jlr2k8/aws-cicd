# VPN Infrastructure

This directory contains the CloudFormation template for the OpenVPN server that provides secure access to the dev-dev-box EC2 instance.

## Files

- **`create-openvpn-simple.yaml`** - Main CloudFormation template for OpenVPN server deployment

## Deployment

The OpenVPN server is deployed using the stack `openvpn-server` with a configurable Elastic IP and DNS record.

## Connection Instructions

1. SSH to the OpenVPN server: `ssh -i your-key.pem ec2-user@vpn.jrog.io`
2. Create a client certificate: `sudo /home/ec2-user/create-client.sh your-name`
3. Download the .ovpn file: `scp -i your-key.pem ec2-user@vpn.jrog.io:/home/ec2-user/your-name.ovpn .`
4. Import the .ovpn file into your OpenVPN client
5. Connect to the VPN
6. Access your dev-dev-box:
   - SSH: `ssh ec2-user@10.0.1.96` (use private IP)
   - RDP: `mstsc /v:10.0.1.96` (Windows Server 2025)

## Security

- Certificate-based authentication
- AES-256-GCM encryption
- TLS authentication
- Private network access only