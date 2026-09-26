#!/usr/bin/env bash
# Install and configure a WireGuard VPN server on Debian/Ubuntu.
#
# Usage: sudo ./install-server.sh
#
# Optional environment overrides:
#   WG_ENDPOINT  public IP or hostname clients connect to (auto-detected)
#   WG_PORT      UDP listen port (default 51820)
#   WG_DNS       DNS servers handed to clients (default 1.1.1.1, 1.0.0.1)
#   WG_SUBNET    first three octets of the VPN subnet (default 10.8.0)
set -euo pipefail

WG_IF=wg0
WG_DIR=/etc/wireguard
WG_CONF="$WG_DIR/$WG_IF.conf"
PARAMS="$WG_DIR/cvpn.params"

WG_PORT="${WG_PORT:-51820}"
WG_DNS="${WG_DNS:-1.1.1.1, 1.0.0.1}"
WG_SUBNET="${WG_SUBNET:-10.8.0}"

die() { echo "error: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (sudo $0)"
[[ -f $WG_CONF ]] && die "$WG_CONF already exists; refusing to overwrite it"
command -v apt-get >/dev/null || die "only Debian/Ubuntu (apt) is supported"
if ! [[ $WG_PORT =~ ^[0-9]+$ ]] || (( WG_PORT < 1 || WG_PORT > 65535 )); then
  die "WG_PORT must be a number between 1 and 65535"
fi

echo "==> Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q wireguard iptables qrencode curl

# The network interface that reaches the internet; VPN traffic is NATed out of it.
WAN_IF="$(ip -4 route show default | awk '{print $5; exit}')"
[[ -n $WAN_IF ]] || die "could not detect the default network interface"

if [[ -z ${WG_ENDPOINT:-} ]]; then
  WG_ENDPOINT="$(curl -4 -fsS --max-time 10 https://api.ipify.org || true)"
  [[ -n $WG_ENDPOINT ]] || die "could not detect the public IP; set WG_ENDPOINT"
fi

echo "==> Enabling IP forwarding"
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-cvpn.conf
sysctl -q --system

echo "==> Generating server keys"
umask 077
mkdir -p "$WG_DIR/clients"
SERVER_PRIV="$(wg genkey)"
SERVER_PUB="$(echo "$SERVER_PRIV" | wg pubkey)"

cat > "$WG_CONF" <<EOF
[Interface]
Address = $WG_SUBNET.1/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
PostUp = iptables -t nat -A POSTROUTING -s $WG_SUBNET.0/24 -o $WAN_IF -j MASQUERADE; iptables -I FORWARD 1 -i $WG_IF -j ACCEPT; iptables -I FORWARD 1 -o $WG_IF -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s $WG_SUBNET.0/24 -o $WAN_IF -j MASQUERADE; iptables -D FORWARD -i $WG_IF -j ACCEPT; iptables -D FORWARD -o $WG_IF -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
EOF

cat > "$PARAMS" <<EOF
WG_IF=$WG_IF
WG_ENDPOINT=$WG_ENDPOINT
WG_PORT=$WG_PORT
WG_DNS="$WG_DNS"
WG_SUBNET=$WG_SUBNET
SERVER_PUB=$SERVER_PUB
EOF

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  echo "==> Opening UDP $WG_PORT in ufw"
  ufw allow "$WG_PORT/udp"
fi

echo "==> Starting WireGuard"
systemctl enable --now "wg-quick@$WG_IF"

cat <<EOF

WireGuard server is running on $WG_ENDPOINT:$WG_PORT/udp.

If your cloud provider has its own firewall (AWS security group, Oracle/GCP
VPC rules, etc.), allow inbound UDP $WG_PORT there too.

Next, add your iPhone:
  sudo $(dirname "$0")/add-client.sh iphone
EOF
