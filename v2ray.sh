read -p "[?] Domain: " -r DOMAIN
read -p "[?] Port: " -r PORT
UUID=`uuidgen`

choices=("none" "srtp" "utp" "wechat-video" "dtls" "wireguard")
for ((i=1; i<=${#choices[@]}; i++)); do
  echo "$((i)). ${choices[i]}"
done
read -p "[?] Select header type: " choice
QUIC_HEADER_TYPE="${choices[choice]}"
echo "You selected: $QUIC_HEADER_TYPE"

choices=("none" "aes-128-gcm" "chacha20-poly1305")
for ((i=1; i<=${#choices[@]}; i++)); do
  echo "$((i)). ${choices[i]}"
done
read -p "[?] Select header type: " choice
QUIC_SECURITY="${choices[choice]}"
echo "You selected: $QUIC_SECURITY"

read -p "[?] Input QUIC key: " -r QUIC_KEY

echo ====INFO====
echo Domain: ${DOMAIN}
echo Port: ${PORT}
echo UUID: ${UUID}
echo QUIC settings:
echo header type: ${QUIC_HEADER_TYPE}
echo security: ${QUIC_SECURITY}
echo key: ${QUIC_KEY}
read -p "[?] Confirm (Y) " confirm
[ ! "${confirm,,}" = "y" ] && exit

echo [+] UFW
ufw allow in http
ufw allow in https
ufw allow in ${PORT}

stage_cert() {
  echo [+] Certbot for ${DOMAIN}
  snap install --classic certbot
  certbot certonly --agree-tos --standalone --register-unsafely-without-email -d ${DOMAIN}
  
  echo [+] Installing certs ${DOMAIN}
  install -D -m 600 -o nobody -g nogroup /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /v2ray/fullchain.pem
  install -D -m 600 -o nobody -g nogroup /etc/letsencrypt/live/${DOMAIN}/privkey.pem /v2ray/privkey.pem
}
[ ! -f /v2ray/fullchain.pem ] && stage_cert

stage_v2ray() {
  echo [+] Compile and install V2ray
  snap install --classic go
  git clone https://github.com/v2fly/v2ray-core
  cd v2ray-core
  go build -o v2ray -trimpath -ldflags "-s -w -buildid=" ./main
  install -D v2ray /v2ray/v2ray

  echo [+] Installing V2ray geoip
  curl -s -L -o /v2ray/geoip.dat "https://github.com/v2fly/geoip/raw/release/geoip.dat"
}
[ ! -f /v2ray/v2ray] && stage_v2ray

echo [+] Configuring V2ray
cat > /v2ray/server.json <<EOF
{
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "quic",
        "quicSettings": {
          "header": {
            "type": "${QUIC_HEADER_TYPE}"
          },
          "key": "${QUIC_KEY}",
          "security": "${QUIC_SECURITY}"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/v2ray/fullchain.pem",
              "keyFile": "/v2ray/privkey.pem"
            }
          ]
        }
      }
    }
  ],
  "log": {
    "access": "none",
    "loglevel": "none"
  },
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block",
        "type": "field"
      }
    ]
  }
}
EOF

cat > /etc/systemd/system/v2ray.service <<EOF
[Unit]
Description=V2Ray Service
After=network.target nss-lookup.target

[Service]
User=nobody
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=/v2ray/v2ray run -config /v2ray/server.json

[Install]
WantedBy=multi-user.target
EOF

systemctl enable v2ray.service
systemctl start v2ray.service
