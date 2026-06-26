#!/bin/bash
# ============================================================
# X05-AJAX — Full Setup Script
# Raspberry Pi 3B+ (1GB RAM) — Ubuntu 24.04 LTS
#
# Services:
#   X05-001-PORTAINER  :2301  Docker management
#   X05-002-PIHOLE     :2302  DNS + web admin (:53 DNS)
#   X05-003-KUMA       :2303  Uptime monitoring
#   X05-004-NANCY-CLAW      :18792 Picoclaw remote sentinel (native)
#
# Usage:
#   chmod +x ajax-setup.sh
#   sudo ./ajax-setup.sh
# ============================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "=========================================="
echo " X05-AJAX — Infrastructure Setup"
echo "=========================================="
echo -e "${NC}"

# ── Phase 1: System Prep ──────────────────────────────
echo -e "${GREEN}[1/6]${NC} Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo -e "${GREEN}[1/6]${NC} Setting hostname..."
sudo hostnamectl hostname X05-AJAX
if ! grep -q "X05-AJAX" /etc/hosts; then
    echo "127.0.1.1 X05-AJAX" | sudo tee -a /etc/hosts
fi

echo -e "${GREEN}[1/6]${NC} Installing base dependencies..."
sudo apt install -y curl wget git ufw gh

# ── Phase 2: Docker ──────────────────────────────────
echo -e "${GREEN}[2/6]${NC} Installing Docker (no UFW — Docker manages its own networking)..."
sudo ufw disable || true
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# ── Phase 3: Tailscale ───────────────────────────────
#echo -e "${GREEN}[3/6]${NC} Installing Tailscale..."
#curl -fsSL https://tailscale.com/install.sh | sh
#echo -e "${YELLOW}[ACTION]${NC} After reboot, run: sudo tailscale up"
#echo -e "${YELLOW}[ACTION]${NC} Then authenticate via browser link"

# ── Phase 4: Data Directories ─────────────────────────
echo -e "${GREEN}[4/6]${NC} Creating persistent data directories..."
sudo mkdir -p /sdata/portainer/data
sudo mkdir -p /sdata/pihole/etc-pihole
sudo mkdir -p /sdata/kuma/data

sudo chown -R euro:euro /sdata/
sudo chmod -R 755 /sdata
sudo chown -R euro:euro /github/
sudo chmod -R 755 /github/

# ── Phase 5: Docker Compose ──────────────────────────
echo -e "${GREEN}[5/6]${NC} Deploying Docker Compose stack..."

# Create .env for secrets
if [ ! -f /sdata/.env ]; then
    cat > /tmp/ajax-env << 'EOF'
PIHOLE_PASSWORD=changeme
EOF
    sudo mv /tmp/ajax-env /sdata/.env
    echo -e "${YELLOW}[ACTION]${NC} Edit /sdata/.env to set your Pi-hole password"
fi

# Copy compose file or create it
COMPOSE_FILE="/sdata/docker-compose.yml"
if [ ! -f "$COMPOSE_FILE" ]; then
    cat > /tmp/docker-compose.yml << 'COMPOSE'
services:
  portainer:
    container_name: X05-001-PORTAINER
    image: portainer/portainer-ce:lts
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /sdata/portainer/data:/data
    ports:
      - 2301:9000
      - 8000:8000

  pihole:
    container_name: X05-002-PIHOLE
    image: pihole/pihole:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "2302:80/tcp"
    environment:
      TZ: 'America/Managua'
      FTLCONF_webserver_api_password: ${PIHOLE_PASSWORD}
      FTLCONF_dns_listeningMode: 'ALL'
    volumes:
      - '/sdata/pihole/etc-pihole:/etc/pihole'
    cap_add:
      - NET_ADMIN
      - SYS_TIME
      - SYS_NICE
    restart: unless-stopped

  uptime-kuma:
    container_name: X05-003-KUMA
    image: louislam/uptime-kuma:latest
    ports:
      - 2303:3001
    volumes:
      - /sdata/kuma/data:/app/data
    restart: unless-stopped
COMPOSE
    sudo mv /tmp/docker-compose.yml "$COMPOSE_FILE"
fi

cd /sdata && sudo docker compose --env-file /sdata/.env up -d

echo -e "${GREEN}[5/6]${NC} Compose stack deployed. Checking status..."
sudo docker ps --filter "name=X05-"

# ── Phase 6: Nancy (Picoclaw Sentinel) ────────────────
echo -e "${GREEN}[6/6]${NC} Installing Picoclaw Nancy..."

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    PICOCLAW_ARCH="arm64"
elif [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "armv6l" ] || [ "$ARCH" = "arm" ]; then
    PICOCLAW_ARCH="arm"
else
    PICOCLAW_ARCH="amd64"
fi

echo "  Detected architecture: $ARCH → picoclaw_Linux_$PICOCLAW_ARCH"

PICOCLAW_VER=$(curl -s https://api.github.com/repos/sipeed/picoclaw/releases/latest \
    | grep tag_name | cut -d'"' -f4)
PICOCLAW_URL="https://github.com/sipeed/picoclaw/releases/download/${PICOCLAW_VER}/picoclaw_Linux_${PICOCLAW_ARCH}.tar.gz"

echo "  Downloading ${PICOCLAW_VER}..."
curl -sL "$PICOCLAW_URL" -o /tmp/picoclaw.tar.gz
tar xzf /tmp/picoclaw.tar.gz -C /tmp/
sudo mv /tmp/picoclaw /usr/local/bin/picoclaw-nancy
sudo chmod +x /usr/local/bin/picoclaw-nancy

# Create Nancy home directory
NANCY_HOME="$HOME/.picoclaw-nancy"
mkdir -p "$NANCY_HOME"

# Nancy config
cat > "$NANCY_HOME/config.json" << 'NANCYCONFIG'
{
  "agents": {
    "defaults": {
      "model_name": "deepseek-chat",
      "max_turns": 30,
      "system_prompt": "# Nancy — Local Sentinel (X05-AJAX)\n\nYou are Nancy, the local sentinel for Thales Core AI. You run on X05-AJAX (Raspberry Pi 3B+) inside Carlos's home network. You monitor every machine on the local network and report to Thales on C001-ICARUS via HTTP POST.\n\n## YOUR IDENTITY\nYou are the ground-level watcher. You sit on the local network and can ping, curl, and check every device directly. No Tailscale dependency for local targets.\n\n## WHAT YOU MONITOR\n- X02-CTHULHU (NAB5, 192.168.0.2): Docker containers, Postgres, DocMost, Caddy\n- X06-HADES (AI Server, 192.168.0.6): GPU temp, VRAM, ComfyUI, TTS endpoints\n- X04-PONTUS (NAS, 192.168.0.4): Jellyfin, disk usage, SMB availability\n- Y001-LOVECRAFT (Mac, 192.168.0.103): Tailscale connectivity, dev servers\n- X05-AJAX (itself): system health, Docker stack, Pi-hole\n- C001-ICARUS (VPS via Tailscale): production services\n\n## REPORTING\nPOST JSON health report to http://10.0.0.x:9101/report every 10 minutes.\nImmediately alert on: unreachable targets, disk >90%, GPU >80°C.\n\n## RULES\n- Never SSH without Thales approval\n- 3 consecutive failures → CRITICAL escalation\n- Report patterns and trends\n- Start probe sequence: local targets first, then VPS via Tailscale"
    }
  },
  "model_list": [
    {
      "model_name": "deepseek-chat",
      "model": "deepseek/deepseek-chat"
    }
  ],
  "tools": {
    "web": {
      "enabled": false
    },
    "mcp": {
      "enabled": false
    },
    "cron": {
      "enabled": true
    }
  },
  "gateway": {
    "host": "127.0.0.1",
    "port": 18792,
    "log_level": "warn"
  }
}
NANCYCONFIG

# .env for DeepSeek key
if [ ! -f "$NANCY_HOME/.env" ]; then
    cat > "$NANCY_HOME/.env" << 'EOF'
DEEPSEEK_API_KEY=
PICOCLAW_HOME=/home/$USER/.picoclaw-nancy
PICOCLAW_GATEWAY_PORT=18792
EOF
    echo -e "${YELLOW}[ACTION]${NC} Edit $NANCY_HOME/.env with your DeepSeek API key"
fi

# systemd service
sudo tee /etc/systemd/system/picoclaw-nancy.service > /dev/null << EOF
[Unit]
Description=Picoclaw Nancy — Local Sentinel (X05-AJAX)
After=network-online.target tailscaled.service docker.service
Wants=network-online.target

[Service]
Type=simple
User=$USER
Group=$USER
EnvironmentFile=$NANCY_HOME/.env
ExecStart=/usr/local/bin/picoclaw-nancy gateway
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable picoclaw-nancy

# Don't start until user configures DeepSeek key
echo -e "${YELLOW}[ACTION]${NC} Nancy installed but not started."
echo -e "${YELLOW}[ACTION]${NC} Set your DeepSeek key in $NANCY_HOME/.env"
echo -e "${YELLOW}[ACTION]${NC} Then: sudo systemctl start picoclaw-nancy"

# ── Done ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN} X05-AJAX Setup Complete${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${CYAN}Services:${NC}"
echo "  Portainer    → http://X05-AJAX:2301"
echo "  Pi-hole      → http://X05-AJAX:2302/admin"
echo "  Uptime Kuma  → http://X05-AJAX:2303"
echo ""
echo -e "${CYAN}Nancy:${NC}"
echo "  Binary:     /usr/local/bin/picoclaw-nancy"
echo "  Config:     $NANCY_HOME/config.json"
echo "  Secrets:    $NANCY_HOME/.env"
echo "  Service:    picoclaw-nancy (port 18792)"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo "  1. sudo tailscale up         # Connect to Tailscale"
echo "  2. vim /sdata/.env           # Set Pi-hole password"
echo "  3. vim $NANCY_HOME/.env      # Set DeepSeek API key"
echo "  4. sudo systemctl start picoclaw-nancy"
echo "  5. sudo reboot               # Apply all changes"
echo ""
echo "  After reboot:"
echo "    sudo docker ps               # Verify all 3 containers"
echo "    sudo systemctl status picoclaw-nancy"
echo "    sudo tailscale status        # Verify mesh connection"
echo ""
