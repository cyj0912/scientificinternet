apt update
apt upgrade -y
apt install -y trojan
snap install --classic certbot
apt install -y nginx

echo [+] Setup firewall
ufw allow in http
ufw allow in https

read -p '[?] Domain: ' DOMAIN
read -p '[?] UUID if you have one: ' UUID
if [ -z $UUID ]; then UUID=`uuidgen`; fi

# Nginx
echo [+] Prepare Nginx homepage
curl -sLf 'https://microsoft.com' > /var/www/html/index.html

# Certbot
echo [+] Fetching certificate for $DOMAIN
systemctl stop nginx
certbot certonly --agree-tos --standalone --register-unsafely-without-email -d ${DOMAIN}
systemctl start nginx

# Install certificates for Trojan
echo [+] Installing certificate for $DOMAIN to trojan dir
install -m 600 -o nobody -g nogroup /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/trojan/fullchain.pem
install -m 600 -o nobody -g nogroup /etc/letsencrypt/live/${DOMAIN}/privkey.pem /etc/trojan/privkey.pem

# Trojan
echo [+] Configuring trojan
tee /etc/trojan/config.json <<EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "${UUID}"
    ],
    "log_level": 5,
    "ssl": {
        "cert": "/etc/trojan/fullchain.pem",
        "key": "/etc/trojan/privkey.pem"
    }
}
EOF
systemctl enable trojan.service
systemctl restart trojan.service

echo Run the following to setup Cloudflare WARP
echo 'bash <(curl -fsSL git.io/warp.sh) wgd'
