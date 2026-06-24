# L001-AJAX-Setup

> Infrastructure setup for **X05-AJAX** — Raspberry Pi 3B+ (1GB RAM, Ubuntu 24.04 LTS)

## Services

| Service | Container | Port | Purpose |
|---------|-----------|------|---------|
| Portainer | `X05-001-PORTAINER` | 2301 | Docker management UI |
| Pi-hole | `X05-002-PIHOLE` | 2302 (web), 53 (DNS) | Network-wide ad blocking |
| Uptime Kuma | `X05-003-KUMA` | 2303 | Service uptime monitoring |

Plus **Nancy** — a Picoclaw remote sentinel agent (native systemd service) that monitors all devices on the local network.

## Prerequisites

- Raspberry Pi 3B+ (or similar ARM device)
- Ubuntu 24.04 LTS installed (fresh)
- Git installed (`sudo apt install -y git`)

## Usage

```bash
# Clone this repo into /sdata
sudo mkdir -p /sdata
cd /sdata
sudo git clone https://github.com/Thales-Core-AI/l001-ajax-setup.git .

# Make executable and run
chmod +x ajax-setup.sh
sudo ./ajax-setup.sh
```

## Post-Install Steps

After the script completes:

```bash
# 1. Connect to Tailscale mesh
sudo tailscale up

# 2. Set Pi-hole web password
vim /sdata/.env
# Set PIHOLE_PASSWORD=your-password

# 3. Set DeepSeek API key for Nancy
vim ~/.picoclaw-nancy/.env
# Set DEEPSEEK_API_KEY=sk-your-key

# 4. Start Nancy
sudo systemctl start picoclaw-nancy

# 5. Reboot
sudo reboot
```

## Verification

```bash
# Check all containers are running
sudo docker ps

# Check Nancy is alive
sudo systemctl status picoclaw-nancy

# Check Tailscale mesh
tailscale status

# Access web UIs:
#   http://X05-AJAX:2301   — Portainer
#   http://X05-AJAX:2302/admin — Pi-hole
#   http://X05-AJAX:2303   — Uptime Kuma
```
