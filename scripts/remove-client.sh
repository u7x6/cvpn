#!/usr/bin/env bash
# Revoke a device's VPN access.
#
# Usage: sudo ./remove-client.sh <name>
set -euo pipefail

WG_DIR=/etc/wireguard
PARAMS="$WG_DIR/cvpn.params"

die() { echo "error: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (sudo $0 <name>)"
[[ $# -eq 1 ]] || die "usage: $0 <name>"
NAME="$1"
[[ $NAME =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "invalid name"
[[ -f $PARAMS ]] || die "$PARAMS not found; run install-server.sh first"
# shellcheck source=/dev/null
source "$PARAMS"

WG_CONF="$WG_DIR/$WG_IF.conf"
grep -qx "### begin $NAME" "$WG_CONF" || die "client '$NAME' not found"

# Drop the peer block (and the blank line before it) between its markers.
tmp="$(mktemp)"
awk -v n="$NAME" '
  $0 == "### begin " n { skip = 1; if (blank) blank = 0; next }
  $0 == "### end " n   { skip = 0; next }
  skip                 { next }
  { if (blank) print ""; blank = ($0 == ""); if (!blank) print }
  END { if (blank) print "" }
' "$WG_CONF" > "$tmp"
cat "$tmp" > "$WG_CONF"   # keeps the original file's permissions
rm -f "$tmp"

wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")
rm -f "$WG_DIR/clients/$NAME.conf" "$WG_DIR/clients/$NAME.png"

echo "Client '$NAME' removed."
