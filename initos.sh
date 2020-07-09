#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

echo 'A1234567b@2020'| passwd --stdin root

yum install git -y

git clone https://github.com/magnific0/wondershaper.git
cd wondershaper
make install

cat > /etc/systemd/wondershaper.conf <<EOF

# Adapter
IFACE="eth0"

# Download rate in Kbps
DSPEED="204800"

# Upload rate in Kbps
USPEED="20000"

### Separate items by whitespace:

#HIPRIODST=(IP1 IP2)
HIPRIODST=()

COMMONOPTIONS=()

# low priority OUTGOING traffic - you can leave this blank if you want
# low priority source netmasks
NOPRIOHOSTSRC=(80);

# low priority destination netmasks
NOPRIOHOSTDST=();

# low priority source ports
NOPRIOPORTSRC=();

# low priority destination ports
NOPRIOPORTDST=();

### EOF

EOF

systemctl daemon-reload
systemctl enable wondershaper
systemctl stop wondershaper
systemctl start wondershaper


rm -rf /root/initos.sh
rm -rf /root/wondershaper
