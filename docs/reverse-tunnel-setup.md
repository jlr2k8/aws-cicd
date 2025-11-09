# Reverse SSH Tunnel Setup and Troubleshooting Guide

## Overview

This document describes how to set up and maintain a reverse SSH tunnel that allows you to access your home network from anywhere on the internet via an EC2 instance in AWS.

### How It Works

A reverse SSH tunnel works by establishing an outbound SSH connection from your home network to an EC2 instance, then forwarding a port on the EC2 instance back to a service on your home network.

1. Your home server establishes an SSH connection to the EC2 instance with reverse port forwarding enabled
2. The EC2 instance listens on a public port (e.g., 9000)
3. Connections to that port on the EC2 instance are forwarded through the SSH tunnel to your home server
4. You can then SSH to the EC2 instance on the tunnel port to access your home network

### Architecture

```
Internet -> EC2 Instance:9000 -> SSH Tunnel -> Home Server:22
```

The tunnel bypasses your router's port forwarding and firewall, as the connection is initiated from inside your network.

## Prerequisites

- AWS account with appropriate permissions
- EC2 keypair for accessing the EC2 instance
- Home server with SSH access
- Route53 hosted zone (optional, for DNS)
- AWS CLI installed and configured
- SSH client on home server
- autossh installed on home server (recommended for automatic reconnection)

## CloudFormation Setup

### Step 1: Create EC2 Keypair

Create a new EC2 keypair in AWS:

```bash
aws ec2 create-key-pair --key-name your-tunnel-key --query 'KeyMaterial' --output text > your-tunnel-key.pem
chmod 600 your-tunnel-key.pem
```

Save the private key securely. You will need it on your home server.

### Step 2: Deploy CloudFormation Stack

Deploy the CloudFormation template with the following parameters:

- KeyPairName: The name of the EC2 keypair you created
- AvailabilityZone: The AWS availability zone for the instance
- InstanceType: EC2 instance type (default: t2.micro)
- SSHLocation: IP range allowed to SSH to EC2 (default: 0.0.0.0/0)
- TunnelPort: Port on EC2 that will be used for the tunnel (default: 9000)
- LocalServicePort: Port on your home server that the tunnel connects to (typically 22 for SSH)
- HostedZoneId: Route53 hosted zone ID (optional)
- HostedZoneName: Your domain name (optional)
- SubdomainName: Subdomain for the tunnel (default: tunnel)

Example deployment:

```bash
aws cloudformation create-stack \
  --stack-name reverse-tunnel \
  --template-body file://cfn-templates/ec2/create-reverse-tunnel-ec2.yaml \
  --parameters \
    ParameterKey=KeyPairName,ParameterValue=your-tunnel-key \
    ParameterKey=AvailabilityZone,ParameterValue=us-west-2a \
    ParameterKey=TunnelPort,ParameterValue=9000 \
    ParameterKey=LocalServicePort,ParameterValue=22 \
    ParameterKey=HostedZoneId,ParameterValue=Z1234567890ABC \
    ParameterKey=HostedZoneName,ParameterValue=example.com \
    ParameterKey=SubdomainName,ParameterValue=tunnel
```

### Step 3: Verify EC2 Instance Configuration

The CloudFormation template automatically configures the EC2 instance with:

- GatewayPorts yes: Allows binding to all interfaces (required for *:port syntax)
- AllowTcpForwarding yes: Enables port forwarding
- Security group rules for SSH (port 22) and tunnel port
- Elastic IP address
- Route53 DNS record (if provided)

Verify the SSH configuration on the EC2 instance:

```bash
ssh -i your-tunnel-key.pem ec2-user@tunnel.example.com 'sudo grep -E "GatewayPorts|AllowTcpForwarding" /etc/ssh/sshd_config'
```

Expected output:
```
GatewayPorts yes
AllowTcpForwarding yes
```

## Home Server Setup

### Step 1: Install autossh

On your home server (Ubuntu/Debian):

```bash
sudo apt-get update
sudo apt-get install autossh
```

### Step 2: Copy Private Key to Home Server

Copy the private key file to your home server:

```bash
scp your-tunnel-key.pem user@home-server:/home/user/.ssh/tunnel-key.pem
```

Or manually copy the key contents and create the file.

Set proper permissions:

```bash
chmod 600 /home/user/.ssh/tunnel-key.pem
```

### Step 3: Test SSH Connection

Test that you can SSH to the EC2 instance from your home server:

```bash
ssh -i /home/user/.ssh/tunnel-key.pem ec2-user@tunnel.example.com 'echo Connection successful'
```

If prompted about host key verification, accept it. The host key will be added to known_hosts.

### Step 4: Establish Reverse Tunnel

Test the tunnel manually first (without -f to see output):

```bash
autossh -M 0 \
  -o "ServerAliveInterval 30" \
  -o "ServerAliveCountMax 3" \
  -N \
  -R '*:9000:localhost:22' \
  ec2-user@tunnel.example.com \
  -i /home/user/.ssh/tunnel-key.pem
```

Parameters explained:
- -M 0: Disable autossh monitoring port (not needed for simple tunnels)
- ServerAliveInterval: Send keepalive every 30 seconds
- ServerAliveCountMax: Maximum keepalive failures before disconnect
- -N: No remote command execution
- -R '*:9000:localhost:22': Reverse tunnel - bind to all interfaces on EC2 port 9000, forward to localhost:22
- -i: Path to private key

The * in '*:9000' requires GatewayPorts yes on the EC2 instance.

Replace 9000 with your chosen tunnel port and 22 with the port your service listens on.

### Step 5: Verify Tunnel is Active

From your home server, check if the tunnel port is listening on the EC2 instance:

```bash
ssh -i /home/user/.ssh/tunnel-key.pem ec2-user@tunnel.example.com 'sudo ss -tlnp | grep 9000'
```

Expected output:
```
LISTEN 0 128 0.0.0.0:9000 0.0.0.0:* users:(("sshd",pid=XXXX,fd=X))
```

Replace 9000 with your actual tunnel port.

### Step 6: Configure Automatic Startup

Add a cron job to start the tunnel on boot:

```bash
crontab -e
```

Add this line (replace 9000 with your tunnel port and 22 with your service port):

```
@reboot sleep 30 && /usr/bin/autossh -M 0 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -N -R '*:9000:localhost:22' ec2-user@tunnel.example.com -i /home/user/.ssh/tunnel-key.pem -f > /dev/null 2>&1
```

The sleep 30 gives the system time to establish network connectivity before starting the tunnel.

## Using the Tunnel

Once the tunnel is established, you can connect to your home network from anywhere:

```bash
ssh -p 9000 username@tunnel.example.com
```

This connects to port 9000 on the EC2 instance, which forwards through the tunnel to port 22 on your home server. Replace 9000 with your actual tunnel port.

## Troubleshooting

### Issue: Tunnel Not Establishing

**Symptoms:** Tunnel port not listening on EC2 instance

**Diagnosis Steps:**

1. Check if autossh process is running on home server:
   ```bash
   ps aux | grep autossh | grep -v grep
   ```

2. Check if SSH tunnel process exists:
   ```bash
   ps aux | grep "ssh.*9000" | grep -v grep
   ```
   Replace 9000 with your tunnel port.

3. Test SSH connection to EC2:
   ```bash
   ssh -i /home/user/.ssh/tunnel-key.pem ec2-user@tunnel.example.com 'echo Connection successful'
   ```

4. Check EC2 SSH configuration:
   ```bash
   ssh -i /home/user/.ssh/tunnel-key.pem ec2-user@tunnel.example.com 'sudo grep -E "GatewayPorts|AllowTcpForwarding" /etc/ssh/sshd_config'
   ```

5. Try starting tunnel manually without -f to see errors:
   ```bash
   autossh -M 0 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -N -R '*:9000:localhost:22' ec2-user@tunnel.example.com -i /home/user/.ssh/tunnel-key.pem
   ```
   Replace ports as needed.

**Common Causes and Fixes:**

- Host key changed: Remove old host key from known_hosts
  ```bash
  ssh-keygen -f "/home/user/.ssh/known_hosts" -R "tunnel.example.com"
  ```

- Wrong SSH key: Verify key file path and permissions
  ```bash
  ls -la /home/user/.ssh/tunnel-key.pem
  chmod 600 /home/user/.ssh/tunnel-key.pem
  ```

- GatewayPorts not set: Verify on EC2 and restart sshd if needed
  ```bash
  ssh -i /home/user/.ssh/tunnel-key.pem ec2-user@tunnel.example.com 'sudo sed -i "s/#GatewayPorts no/GatewayPorts yes/" /etc/ssh/sshd_config && sudo systemctl restart sshd'
  ```

- Service port not listening on home server: Verify service is running
  ```bash
  ss -tlnp | grep 22
  ```
  Replace 22 with your actual service port.

### Issue: Permission Denied When Connecting Through Tunnel

**Symptoms:** Can connect to EC2, but get permission denied when using tunnel port

**Diagnosis:**

1. Verify tunnel is active:
   ```bash
   ssh -i /home/user/.ssh/tunnel-key.pem ec2-user@tunnel.example.com 'sudo ss -tlnp | grep 9000'
   ```
   Replace 9000 with your tunnel port.

2. Test connection through tunnel:
   ```bash
   ssh -p 9000 -v username@tunnel.example.com
   ```
   Replace 9000 with your tunnel port.

**Common Causes:**

- Wrong username: Use the username that exists on your home server
- SSH key authentication required: Ensure you have the correct key or password
- Service not running on home server on the expected port

### Issue: Tunnel Disconnects Frequently

**Symptoms:** Tunnel works but drops connection regularly

**Solutions:**

1. Increase keepalive settings in autossh command:
   ```bash
   -o "ServerAliveInterval 60"
   -o "ServerAliveCountMax 5"
   ```

2. Check network stability on home server

3. Verify autossh is configured to restart automatically (it should by default)

### Issue: Host Key Verification Failed

**Symptoms:** Error message about remote host identification changed

**Fix:**

Remove old host key and reconnect:

```bash
ssh-keygen -f "/home/user/.ssh/known_hosts" -R "tunnel.example.com"
ssh -i /home/user/.ssh/tunnel-key.pem ec2-user@tunnel.example.com
```

Answer "yes" when prompted to add the new host key.

### Issue: EC2 Instance Terminated or Recreated

**Symptoms:** Cannot connect to EC2, instance shows as terminated

**Diagnosis:**

Check instance status:

```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=ReverseTunnelInstance" --query 'Reservations[*].Instances[*].[InstanceId,State.Name,KeyName]' --output table
```

**Fix:**

If instance was recreated:
1. Update host key in known_hosts (see above)
2. Verify new instance has correct keypair
3. Restart tunnel from home server

### Issue: Security Group Blocking Connections

**Symptoms:** Cannot connect to tunnel port from internet

**Diagnosis:**

Check security group rules:

```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=ReverseTunnelInstance" --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' --output text | xargs -I {} aws ec2 describe-security-groups --group-ids {} --query 'SecurityGroups[0].IpPermissions[?FromPort==`9000`]' --output table
```

Replace 9000 with your tunnel port.

**Fix:**

Ensure security group allows inbound traffic on tunnel port from 0.0.0.0/0. The CloudFormation template should configure this automatically.

### Issue: Cannot Bind to Port (Address Already in Use)

**Symptoms:** Error about port already in use when starting tunnel

**Diagnosis:**

Check if another tunnel process is running:

```bash
ps aux | grep autossh
ps aux | grep "ssh.*9000"
```
Replace 9000 with your tunnel port.

**Fix:**

Kill existing process:

```bash
kill <PID>
```

Or find and kill:

```bash
pkill -f "autossh.*9000"
```
Replace 9000 with your tunnel port.

## Updating the Setup

### Changing the Keypair

If you need to change the EC2 keypair:

1. Create new keypair in AWS
2. Update CloudFormation stack:
   ```bash
   aws cloudformation update-stack \
     --stack-name reverse-tunnel \
     --use-previous-template \
     --parameters ParameterKey=KeyPairName,ParameterValue=new-key-name <other-parameters>
   ```

3. Copy new private key to home server
4. Update cron job with new key path
5. Remove old host key and test connection
6. Restart tunnel

### Changing Tunnel Port

1. Update CloudFormation stack with new TunnelPort parameter
2. Update security group (if not done automatically)
3. Update autossh command on home server with new port
4. Update cron job
5. Restart tunnel

## Maintenance

### Regular Checks

Periodically verify the tunnel is working:

```bash
# From home server
ssh -i /home/user/.ssh/tunnel-key.pem ec2-user@tunnel.example.com 'sudo ss -tlnp | grep 9000'
```
Replace 9000 with your tunnel port.

### Logs

Check system logs for autossh errors:

```bash
journalctl -u cron | grep autossh
# or
grep autossh /var/log/syslog
```

### Monitoring

Consider setting up monitoring to alert if the tunnel goes down. You can:

1. Periodically test the tunnel connection
2. Monitor the autossh process
3. Check EC2 instance health
4. Set up CloudWatch alarms for EC2 instance status

## Security Considerations

1. Use strong SSH keys (at least 2048-bit RSA or ED25519)
2. Restrict SSH access to EC2 instance (SSHLocation parameter)
3. Use a dedicated user account on home server for the tunnel
4. Regularly rotate SSH keys
5. Monitor for unauthorized access attempts
6. Consider using SSH certificates for additional security
7. Keep EC2 instance and home server updated with security patches

## Additional Notes

- The tunnel requires the home server to initiate the connection, so it works even behind NAT/firewall
- If your home server IP changes, the tunnel will automatically reconnect (with autossh)
- The EC2 instance must have GatewayPorts yes for the *:port syntax to work
- Port 22 in examples is the standard SSH port - adjust to match your home server's SSH port
- The tunnel port (9000 in examples) and local service port (22 in examples) can be any ports you choose
- Replace all example port numbers (9000, 22) with your actual configured ports throughout this document