#!/usr/bin/env bash
sudo yum install bind-utils
wget -qO /usr/local/bin/ddns.sh https://raw.githubusercontent.com/oswaldlau/shell/master/ddns.sh
read -p "动态域名:" inputDomain
read -p "公云用户名:" inputUser
read -p "公云密码:" inputPassword
sed -i '2s/setDomain/$inputDomain/g' /usr/local/bin/ddns.sh
sed -i '3s/setUser/$inputUser/g' /usr/local/bin/ddns.sh
sed -i '4s/setPassword/$inputPassword/g' /usr/local/bin/ddns.sh

#配置定时任务

cat >/lib/systemd/system/ddns.service <<EOF
[Unit]
Description=设置ddns
After=network-online.target
Wants=network-online.target
[Service]
WorkingDirectory=/root/
EnvironmentFile=
ExecStart=/bin/bash /usr/local/bin/ddns.sh
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ddns >/dev/null 2>&1
service ddns stop >/dev/null 2>&1
service ddns start >/dev/null 2>&1
