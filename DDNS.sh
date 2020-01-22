#!/usr/bin/env bash

read -p "动态域名:" Domain
read -p "公云用户名:" User
read -p "公云密码:" Password

#写入执行脚本
cat >/usr/local/bin/ddns.sh <<EOF
#!/usr/bin/env bash


GETDomainIP=$(nslookup $Domain 2>&1)
DomainIP=$(echo "$GETDomainIP" | grep 'Address:' | tail -n1 | awk '{print $NF}')
LocalIP="curl -s whatismyip.akamai.com"
if [ "$LocalIP" = "$DomainIP" ]; then
    echo -e "${Msg_Info}当前IP ($AliDDNS_LocalIP) 与 $AliDDNS_SubDomainName.$AliDDNS_DomainName ($AliDDNS_DomainIP) 的IP相同"
    echo -e "${Msg_Success}未发生任何变动，无需进行改动，正在退出……"
    exit 0
    else
    lynx -mime_header -auth=$User:$Password "http://members.3322.net/dyndns/update?system=dyndns&hostname=$Domain" >>/var/log/update_ddns.log
fi
EOF

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
