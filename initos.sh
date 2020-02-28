#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

echo 'A1234567@b'| passwd --stdin root
systemctl stop wondershaper

yum install git -y

git clone https://github.com/magnific0/wondershaper.git
cd wondershaper
make install

cat > /etc/conf.d/wondershaper.conf <<EOF
[wondershaper]
# Adapter
#
IFACE="eth0"

# Download rate in Kbps
#
DSPEED="102400"

# Upload rate in Kbps
#
USPEED="3072"
EOF

systemctl daemon-reload
systemctl enable wondershaper
systemctl stop wondershaper
systemctl start wondershaper


rm -rf /root/initos.sh
rm -rf /root/wondershaper
