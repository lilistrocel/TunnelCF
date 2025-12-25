# Cloudflare Tunnel Auto-Provisioner for Raspberry Pi

Automatically provisions and manages Cloudflare Tunnels for SSH access to Raspberry Pi devices. Each device self-registers with a unique hostname based on its machine ID.

## Features

- **Auto-provisioning**: Automatically creates tunnel and DNS records on first boot
- **Unique identity**: Uses machine ID (CPU serial, MAC address, or system ID) for consistent naming
- **Idempotent**: Safe to restart - detects existing tunnels and reuses them
- **Systemd integration**: Runs as a proper system service with auto-restart
- **Secure**: Credentials stored with restricted permissions
- **Multi-service**: Can expose SSH plus additional services (web, API, etc.)

## Prerequisites

1. A domain added to Cloudflare
2. Cloudflare API Token with permissions:
   - `Account > Cloudflare Tunnel > Edit`
   - `Zone > DNS > Edit`
3. Raspberry Pi with Raspberry Pi OS (or any Debian-based distro)
4. SSH server running on the Pi

## Quick Start

### 1. Get Cloudflare Credentials

**Account ID & Zone ID:**
- Log into [Cloudflare Dashboard](https://dash.cloudflare.com)
- Select your domain
- Find IDs in the right sidebar under "API"

**API Token:**
- Go to [API Tokens](https://dash.cloudflare.com/profile/api-tokens)
- Create Token → Custom Token
- Permissions:
  - Account | Cloudflare Tunnel | Edit
  - Zone | DNS | Edit
- Account Resources: Include your account
- Zone Resources: Include your zone

### 2. Install on Raspberry Pi

```bash
# Download and extract
git clone <your-repo> cf-tunnel-service
# Or copy the files via SCP

cd cf-tunnel-service
sudo ./install.sh
```

The installer will:
- Install cloudflared binary
- Set up the systemd service
- Prompt for configuration (or use config file)

### 3. Connect via SSH

From any machine with cloudflared installed:

```bash
# Your hostname will be: {prefix}-{machine_id}.{domain}
cloudflared access ssh --hostname rpi-abc123def456.yourdomain.com
```

Or add to your `~/.ssh/config`:

```
Host rpi-*
    ProxyCommand cloudflared access ssh --hostname %h.yourdomain.com
```

Then simply: `ssh user@rpi-abc123def456`

## Configuration

Edit `/etc/cf-tunnel/config.env`:

```bash
# Required
CF_API_TOKEN="your-token"
CF_ACCOUNT_ID="your-account-id"
CF_ZONE_ID="your-zone-id"
CF_DOMAIN="yourdomain.com"

# Optional
NODE_PREFIX="rpi"              # Hostname prefix (default: node)
SSH_PORT="22"                  # Local SSH port (default: 22)
ADDITIONAL_SERVICES=""         # Extra services to expose
```

### Exposing Additional Services

To expose more than just SSH, configure `ADDITIONAL_SERVICES`:

```bash
# Format: hostname1:service1,hostname2:service2
ADDITIONAL_SERVICES="web-mypi.example.com:http://localhost:80,api-mypi.example.com:http://localhost:8080"
```

Service URL formats:
- HTTP: `http://localhost:8080`
- HTTPS: `https://localhost:443`
- TCP: `tcp://localhost:3306`
- Unix socket: `unix:/var/run/docker.sock`

## File Locations

| Path | Description |
|------|-------------|
| `/etc/cf-tunnel/config.env` | Configuration (credentials) |
| `/var/lib/cf-tunnel/tunnel-info.json` | Tunnel metadata |
| `/var/lib/cf-tunnel/machine-id` | Persisted machine identity |
| `/usr/local/bin/cf-tunnel-provisioner.sh` | Main script |
| `/usr/local/bin/cloudflared` | Cloudflare daemon |

## Service Management

```bash
# Check status
sudo systemctl status cf-tunnel

# View logs
sudo journalctl -u cf-tunnel -f

# Restart service
sudo systemctl restart cf-tunnel

# Stop service
sudo systemctl stop cf-tunnel

# Disable auto-start
sudo systemctl disable cf-tunnel
```

## Deploying to Multiple Devices

### Option 1: Pre-configured SD Card Image

1. Install on one Pi
2. Configure with credentials
3. Create SD card image
4. Flash to other Pis

Each Pi will get a unique hostname based on its hardware.

### Option 2: Cloud-init / First-boot Script

Add to your provisioning:

```bash
#!/bin/bash
# Download installer
curl -sL https://your-server/cf-tunnel-installer.tar.gz | tar xz -C /opt/
# Write config
cat > /etc/cf-tunnel/config.env << 'EOF'
CF_API_TOKEN="..."
CF_ACCOUNT_ID="..."
CF_ZONE_ID="..."
CF_DOMAIN="..."
NODE_PREFIX="field"
EOF
chmod 600 /etc/cf-tunnel/config.env
# Install and start
cd /opt/cf-tunnel-service && ./install.sh --non-interactive
```

### Option 3: Ansible Playbook

```yaml
- name: Deploy CF Tunnel
  hosts: raspberry_pis
  become: yes
  tasks:
    - name: Copy tunnel service files
      copy:
        src: cf-tunnel-service/
        dest: /opt/cf-tunnel-service/
        mode: preserve

    - name: Install service
      command: /opt/cf-tunnel-service/install.sh --non-interactive
      args:
        creates: /etc/systemd/system/cf-tunnel.service

    - name: Configure tunnel
      template:
        src: config.env.j2
        dest: /etc/cf-tunnel/config.env
        mode: '0600'
      notify: restart cf-tunnel

  handlers:
    - name: restart cf-tunnel
      systemd:
        name: cf-tunnel
        state: restarted
```

## Security Considerations

1. **API Token Scope**: Use minimal permissions (just Tunnel and DNS)
2. **Token Rotation**: Rotate API tokens periodically
3. **Access Policies**: Configure Cloudflare Access to restrict who can SSH
4. **Firewall**: The Pi doesn't need any inbound ports open

### Adding Cloudflare Access Protection

1. Go to Zero Trust → Access → Applications
2. Add Application → Self-hosted
3. Application domain: `*.yourdomain.com` or specific hostnames
4. Add authentication policies (e.g., email OTP, SSO)

## Troubleshooting

### Service won't start

```bash
# Check logs
journalctl -u cf-tunnel -n 50

# Test manually
sudo /usr/local/bin/cf-tunnel-provisioner.sh
```

### "Tunnel already exists" error

The tunnel name is based on machine ID. If you're reusing hardware:

```bash
# Remove persisted machine ID to generate new one
sudo rm /var/lib/cf-tunnel/machine-id
sudo systemctl restart cf-tunnel
```

### DNS record not created

Check API token has `Zone > DNS > Edit` permission for the correct zone.

### Can't connect via SSH

1. Verify tunnel is running: `systemctl status cf-tunnel`
2. Check tunnel status in Cloudflare Dashboard
3. Ensure SSH is running locally: `systemctl status ssh`
4. Verify hostname in `/var/lib/cf-tunnel/tunnel-info.json`

## Cleanup

To remove a device's tunnel:

1. Run uninstaller: `sudo ./uninstall.sh`
2. Delete tunnel in Cloudflare Dashboard: Zero Trust → Networks → Tunnels

## Architecture

```
┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Your Computer     │     │    Cloudflare    │     │  Raspberry Pi   │
│                     │     │                  │     │                 │
│  cloudflared access ├────►│  Zero Trust      │◄────┤  cloudflared    │
│  ssh --hostname ... │     │  Network         │     │  tunnel run     │
│                     │     │                  │     │                 │
└─────────────────────┘     └──────────────────┘     └─────────────────┘
                                    │
                                    ▼
                            DNS: rpi-xxx.domain.com
                                    │
                                    ▼
                            CNAME → tunnel-id.cfargotunnel.com
```

## License

MIT License - Use freely for your A20Core field deployments!
