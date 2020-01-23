#!/usr/bin/env bash
Domain='setDomain'
User='setUser'
Password='setPassword'
GETDomainIP=$(nslookup $Domain 2>&1)
DomainIP=$(echo "$GETDomainIP" | grep 'Address:' | tail -n1 | awk '{print $NF}')
LocalIP="curl -s whatismyip.akamai.com"
if [ "$LocalIP" = "$DomainIP" ]; then
    echo -e "当前IP ($LocalIP) 与 $DomainIP 的IP相同" >>/var/log/update_ddns.log
    echo -e "未发生任何变动，无需进行改动，正在退出……"  >>/var/log/update_ddns.log
    exit 0
else
    lynx -mime_header -auth=$User:$Password "http://members.3322.net/dyndns/update?system=dyndns&hostname=$Domain" >>/var/log/update_ddns.log
fi
