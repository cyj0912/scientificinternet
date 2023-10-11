#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 
    exit 1
fi

# Get Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs)

# Update the system and install software-properties-common
apt update && apt upgrade -y
apt install software-properties-common -y

# Add WireGuard repository for Ubuntu 18.04
if [[ $UBUNTU_VERSION == "18.04" ]]; then
    add-apt-repository ppa:wireguard/wireguard -y
    apt update
    apt install wireguard-dkms wireguard-tools linux-headers-$(uname -r) iptables-persistent -y
else
    apt install wireguard-tools iptables-persistent -y
fi

# Configure WireGuard
umask 077
cd /etc/wireguard
wg genkey | tee privatekey | wg pubkey > publickey

# Prompt user for client's public key
read -p "Enter the client's public key: " CLIENT_PUBLIC_KEY

# Generate server configuration
cat > wg0.conf <<EOL
[Interface]
Address = 10.0.0.1/24
SaveConfig = true
PrivateKey = $(cat privatekey)
ListenPort = 51820

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = 10.0.0.2/32

EOL

# Start and enable WireGuard
systemctl start wg-quick@wg0
systemctl enable wg-quick@wg0

# Enable IP Forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Set up NAT with iptables
iptables -A FORWARD -i wg0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Save iptables rules to be persistent across reboots
iptables-save > /etc/iptables/rules.v4

echo "WireGuard is now set up with forwarding to the internet enabled!"
echo "Client with IP 10.0.0.2 has been added."
