#!/bin/bash

# Update and upgrade system
sudo apt update && sudo apt upgrade -y

# Install wireguard
sudo apt install -y wireguard-tools

# Generate private and public key for wireguard
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

# Generate client keys
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

# Generate random ULA prefix
# ULA prefix is in the range fd00::/8 to fdff::/8
# Generate random hexadecimal values for the subsequent 40 bits
ULA_PREFIX=$(printf "fd%x:%x:%x" "$(($RANDOM/256))" "$RANDOM" "$RANDOM")

# Detect default gateway interface name
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)

# Enable IP forwarding
sudo sh -c 'echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf'
sudo sh -c 'echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf'
sudo sysctl -p

# Allow WireGuard port in UFW
sudo ufw allow 16383/udp

# Write the wg0.conf file
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = 10.8.0.1/24, ${ULA_PREFIX}::1/64
ListenPort = 16383
PostUp = ufw route allow in on wg0 out on ${MAIN_INTERFACE}
PostUp = iptables -t nat -I POSTROUTING -o ${MAIN_INTERFACE} -j MASQUERADE
PostUp = ip6tables -t nat -I POSTROUTING -o ${MAIN_INTERFACE} -j MASQUERADE
PreDown = ufw route delete allow in on wg0 out on ${MAIN_INTERFACE}
PreDown = iptables -t nat -D POSTROUTING -o ${MAIN_INTERFACE} -j MASQUERADE
PreDown = ip6tables -t nat -D POSTROUTING -o ${MAIN_INTERFACE} -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32, ${ULA_PREFIX}::2/64
EOF

# Start and enable WireGuard
systemctl start wg-quick@wg0
systemctl enable wg-quick@wg0

# Echo client config
echo "Client Configuration:"
echo "----------------------"
cat <<EOF

[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.8.0.2/24, ${ULA_PREFIX}::2/64
DNS = 10.8.0.1

[Peer]
PublicKey = $PUBLIC_KEY
Endpoint = [Your-Server-IP]:16383
AllowedIPs = 0.0.0.0/0, ::/0

EOF
