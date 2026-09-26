#!/usr/bin/env bash
# Create a VPN profile for a device and show it as a QR code.
#
# Usage: sudo ./add-client.sh <name>      e.g. sudo ./add-client.sh iphone
#
# Scan the QR code in the WireGuard iOS app: + > Create from QR code.
set -euo pipefail

WG_DIR=/etc/wireguard
PARAMS="$WG_DIR/cvpn.params"

die() { echo "error: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (sudo $0 <name>)"
[[ $# -eq 1 ]] || die "usage: $0 <name>"
NAME="$1"
[[ $NAME =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "name may only use letters, digits, - and _ (max 32)"
[[ -f $PARAMS ]] || die "$PARAMS not found; run install-server.sh first"
# shellcheck source=/dev/null
source "$PARAMS"

WG_CONF="$WG_DIR/$WG_IF.conf"
CLIENT_CONF="$WG_DIR/clients/$NAME.conf"
[[ -e $CLIENT_CONF ]] && die "client '$NAME' already exists"

# Pick the lowest free host address; .1 is the server.
used="$(grep -oP "AllowedIPs = \Q$WG_SUBNET\E\.\K[0-9]+" "$WG_CONF" || true)"
CLIENT_OCTET=""
for i in $(seq 2 254); do
  if ! grep -qx "$i" <<<"$used"; then CLIENT_OCTET=$i; break; fi
done
[[ -n $CLIENT_OCTET ]] || die "no free addresses left in $WG_SUBNET.0/24"
CLIENT_IP="$WG_SUBNET.$CLIENT_OCTET"

umask 077
CLIENT_PRIV="$(wg genkey)"
CLIENT_PUB="$(echo "$CLIENT_PRIV" | wg pubkey)"
PSK="$(wg genpsk)"

cat >> "$WG_CONF" <<EOF

### begin $NAME
[Peer]
PublicKey = $CLIENT_PUB
PresharedKey = $PSK
AllowedIPs = $CLIENT_IP/32
### end $NAME
EOF

# Routing ::/0 through the tunnel too stops IPv6 traffic leaking around the VPN.
cat > "$CLIENT_CONF" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP/32
DNS = $WG_DNS

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $PSK
Endpoint = $WG_ENDPOINT:$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

# Apply the new peer without dropping existing connections.
wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")

qrencode -t png -o "$WG_DIR/clients/$NAME.png" < "$CLIENT_CONF"

echo "Client '$NAME' added with address $CLIENT_IP."
echo "Config: $CLIENT_CONF"
echo "QR PNG: $WG_DIR/clients/$NAME.png"
echo
echo "Scan this in the WireGuard iOS app (+ > Create from QR code):"
qrencode -t ansiutf8 < "$CLIENT_CONF"
