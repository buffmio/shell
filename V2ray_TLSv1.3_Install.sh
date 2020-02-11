#!/usr/bin/env bash


green="\033[32m"
red="\033[31m"
plain='\033[0m'


[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as root!" && exit 1

pre_install(){
    echo -e "请输入一个域名"
    read -p "Domain:" domain
    echo -e "请输入Ali_Key"
    read -p "Ali_Key:" alikey
    echo -e "请输入Ali_Secret"
    read -p "Ali_Secret" alisecret
    

}

configure_repos(){
    yum install epel-release -y
    cat > /etc/yum.repos.d/wlnmp-release-centos.repo << EOF
[wlnmp]
name=wlnmp
baseurl=http://mirrors.wlnmp.com/centos/$releasever/$basearch/
enabled=1
gpgcheck=1
gpgkey=http://mirrors.wlnmp.com/centos/RPM-GPG-KEY-wlnmp
EOF
}

# Disable selinux
disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}
    
install_v2ray(){
    bash <(curl -L -s https://install.direct/go.sh)
    mv /etc/v2ray/config.json /etc/v2ray/config.json.bak
    uuid=$(cat /proc/sys/kernel/random/uuid)
    cat > /etc/v2ray/config.json << EOF
{
  "inbounds": [
    {
      "port": 10000,
      "listen":"127.0.0.1",//只监听 127.0.0.1，避免除本机外的机器探测到开放了 10000 端口
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 64
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
        "path": "/ray"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
    systemctl restart v2ray
    systemctl enable v2ray
}

install_nginx(){
    yum install wnginx -y
    mkdir -p /www/wwwroot/${domain}
    mkdir -p /usr/local/nginx/ssl
    cat > /usr/local/nginx/conf/vhost/${domain}.conf << EOF   
server {
  listen 80;
  listen 443 ssl http2;
  ssl_certificate /usr/local/nginx/ssl/fullchain.cer;
  ssl_certificate_key /usr/local/nginx/ssl/${domain}.key;
  ssl_protocols   TLSv1.3;
  ssl_session_cache shared:SSL:50m;
  ssl_session_timeout 1d;
  ssl_session_tickets off;

  # 启用服务器端保护, 防止 BEAST 攻击
  # http://blog.ivanristic.com/2013/09/is-beast-still-a-threat.html
  ssl_prefer_server_ciphers on;
  # ciphers chosen for forward secrecy and compatibility
  # http://blog.ivanristic.com/2013/08/configuring-apache-nginx-and-openssl-for-forward-secrecy.html
  ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS';

  # 启用 ocsp stapling (网站可以以隐私保护、可扩展的方式向访客传达证书吊销信息的机制)
  # http://blog.mozilla.org/security/2013/07/29/ocsp-stapling-in-firefox/
  resolver 8.8.8.8 8.8.4.4;
  ssl_early_data  on;
  ssl_stapling on;
  ssl_stapling_verify on;
  add_header Strict-Transport-Security max-age=15768000;
  server_name magicmio.site;
  access_log /www/wwwroot/${domain}/nginx.log combined;
  index index.html index.htm index.php;
  root /www/wwwroot/${domain};
  add_header Strict-Transport-Security "max-age=31536000; includeSubdomains; preload";
  if ($ssl_protocol = "") { return 301 https://$host$request_uri; }

  #error_page 404 /404.html;
  #error_page 502 /502.html;

  location /ray {
    proxy_pass       http://127.0.0.1:23333;
    proxy_redirect             off;
    proxy_http_version         1.1;
    proxy_set_header Upgrade   $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host      $http_host;
  }
}
EOF
    curl  https://get.acme.sh | sh
    source .bashrc
    export Ali_Key="${alikey}"
    export Ali_Secret="${alisecret}"
    acme.sh --issue --dns dns_ali -d $domain -d *.${domain} --keylength ec-256
    acme.sh  --installcert  -d  $domain   \
        --key-file   /usr/local/nginx/ssl/${domain}.key \
        --fullchain-file /usr/local/nginx/ssl/fullchain.cer \
        --ecc \
        --reloadcmd  "service nginx reload"
    
}

check_service(){
    ps -ef | grep -v grep | grep -i "v2ray" && ps -ef | grep -v grep | grep -i "nginx" > /dev/null 2>&1
    if [$? -eq 0]; then
    clear
    echo "---------- v2ray Information ----------"
    echo -e "${green}Succ:${plain} 安装已完成"
    echo -e "address : $domain"
    echo -e "port : 443"
    echo -e "uuid : $uuid"
    echo -e "alterid : 64"
    echo -e "network : ws"
    echo -e "path : /ray"
    echo "----------------------------------------"

    else

    echo -e "${red}Error:${plain} 安装失败" && exit 1

    fi
}

inall_step(){
  pre_install
  configure_repos
  disable_selinux
  install_v2ray
  install_nginx
  check_service
}

remove_step(){

    service nginx stop
    yum remove wnginx -y
    rm -rf /usr/local/nginx
    systemctl stop v2ray.service
    systemctl disable v2ray.service
    rm -f /etc/systemd/system/v2ray.service
    systemctl daemon-reload
    rm -rf /usr/bin/v2ray /etc/v2ray
    
    echo -e "${green}Succ:${plain} 删除成功"
    
}

# Initialization step
action=$1
[ -z "$1" ] && action=install
case "$action" in
    install|uninstall)
        ${action}_step
        ;;
    *)
        echo "Arguments error! [${action}]"
        echo "Usage: $(basename $0) [install|uninstall]"
        ;;
esac
