#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

echo 'A1234567b@2020'| passwd --stdin root

yum install wget -y

wget -P /opt https://raw.githubusercontent.com/buffmio/LightsailLimitTraffic/master/1000G.py

cat > /etc/systemd/system/traffic.service <<EOF
[Unit]
Description=traffic
After=rc-local.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt
ExecStart=/usr/bin/python 500G.py
Restart=always

[Install]
WantedBy=multi-user.target

EOF

systemctl daemon-reload
systemctl enable traffic
systemctl start traffic
