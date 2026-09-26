# cvpn

My own personal VPN for iPhone, built on [WireGuard](https://www.wireguard.com/).

You run a small WireGuard server on a cloud VPS. Your iPhone connects to it with
the free official **WireGuard** app from the App Store. All of your phone's traffic
then goes out through your server. You don't need a Mac, Xcode or an Apple
Developer account.

```
iPhone (WireGuard app) ──encrypted UDP──▶ your VPS (wg0) ──▶ internet
```

## What you need

- A Linux VPS with a public IP address, running **Ubuntu 22.04+ or Debian 11+**.
  Any provider works (Hetzner, DigitalOcean, Vultr, Linode, AWS Lightsail, or the
  Oracle Cloud free tier). The smallest plan is enough.
- SSH access to it as root or a sudo user.
- An iPhone with the [WireGuard app](https://apps.apple.com/app/wireguard/id1441195209).

## Setup

### 1. Install the server

SSH into your VPS, then run:

```bash
git clone https://github.com/u7x6/cvpn.git
cd cvpn
sudo ./scripts/install-server.sh
```

The script installs WireGuard, enables IP forwarding and NAT, generates the
server keys and starts the `wg-quick@wg0` service. The service starts again
automatically after a reboot.

You can change the defaults with environment variables:

| Variable      | Default            | Meaning                                  |
|---------------|--------------------|------------------------------------------|
| `WG_ENDPOINT` | auto-detected IP   | Public IP or domain name the phone dials |
| `WG_PORT`     | `51820`            | UDP port                                 |
| `WG_DNS`      | `1.1.1.1, 1.0.0.1` | DNS servers the phone uses on the VPN    |
| `WG_SUBNET`   | `10.8.0`           | VPN subnet (`/24`)                       |

For example: `sudo WG_PORT=443 WG_DNS="9.9.9.9" ./scripts/install-server.sh`

> **Cloud firewall:** if your provider has a firewall outside the server
> (AWS security groups, Oracle/GCP VPC rules, DigitalOcean Cloud Firewalls),
> allow **inbound UDP 51820** there. If you use `ufw` on the server, the
> script already opens the port.

### 2. Add your iPhone

```bash
sudo ./scripts/add-client.sh iphone
```

A QR code appears in your terminal. The profile is also saved to
`/etc/wireguard/clients/iphone.conf` and `iphone.png`.

### 3. Connect from the iPhone

1. Open the **WireGuard** app and tap **+**, then **Create from QR code**.
2. Scan the QR code and give the tunnel a name.
3. Allow iOS to add the VPN configuration.
4. Turn the tunnel on. **VPN** appears in the status bar.

To check that it works, visit <https://ifconfig.me> in Safari. It should show
your server's IP address.

**Tip:** to keep the VPN on all the time, open the tunnel in the WireGuard app,
tap **Edit** and turn on **On-Demand** for Wi-Fi and Cellular.

## Managing devices

Give each device its own profile. Don't share a profile between devices.

```bash
sudo ./scripts/add-client.sh ipad        # add another device
sudo ./scripts/remove-client.sh ipad     # revoke a device
sudo wg show                             # see connected devices and traffic
```

## Troubleshooting

- **The phone connects but no websites load:** the UDP port is probably blocked
  by the cloud firewall. Run `sudo wg show` on the server. If the peer has no
  `latest handshake`, packets are not reaching the server.
- **There is a handshake but still no internet:** check that
  `sysctl net.ipv4.ip_forward` returns `1`. Then check the NAT rule with
  `sudo iptables -t nat -S POSTROUTING`.
- **Some networks block the port:** reinstall with `WG_PORT=443`. Before
  reinstalling, run `sudo systemctl disable --now wg-quick@wg0` and delete
  `/etc/wireguard/wg0.conf`.

## Security notes

- Private keys stay on the server in `/etc/wireguard` with mode `600`. Delete
  `clients/<name>.conf` and `clients/<name>.png` after you import them if you
  don't need them anymore.
- Each device gets a preshared key on top of its key pair.
- The phone routes both IPv4 and IPv6 (`::/0`) through the tunnel, so IPv6
  traffic can't leak around the VPN.
