#!/usr/bin/env bash
#
#Auto install kms server
#system support: ubuntu


red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'


cur_dir=$(pwd)

set_firewall() {

if [ps ax | grep ufw] > /dev/null 2>&1]; then
	ufw allow 1688/tcp
	ufw reload
else
	echo -e “${yellow}Warning:${plain} the firewall not enable or not installed, so do not anything”

fi
}

install_main(){
	echo " Auto install KMS Server"
	echo "Press any key to start...or Press Ctrl+C to cancel"
    read
	
	cd "${cur_dir}" || exit
    wget -c https://github.com/Wind4/vlmcsd/releases/download/svn1111/binaries.tar.gz > /dev/null 2>&1
    tar -xzvf binaries.tar.gz > /dev/null 2>&1
    if [  -d "${cur_dir}"/binaries ]; then
        cp -p ~/binaries/Linux/intel/static/vlmcsd-x64-musl-static /usr/bin/
        chmod 755 /usr/bin/vlmcsd-x64-musl-static

    else

        echo -e "${red}Error:${plain} Install KMS Server failed, please check it and try again."
        exit 1
    fi

    
    echo " ">/var/run/vlmcsd.pid
    
cat > /lib/systemd/system/vlmcsd.service << EOF
 [Unit]
 Description=KMS Server By vlmcsd
 After=network.target
 
 [Service]
 Type=forking
 PIDFile=/var/run/vlmcsd.pid
 ExecStart=/usr/bin/vlmcsd-x64-musl-static -p /var/run/vlmcsd.pid
 ExecStop=/bin/kill -HUP $MAINPID
 PrivateTmp=true
 
 [Install]
 WantedBy=multi-user.target
EOF

 if [ -e /lib/systemd/system/vlmcsd.service ]; then
 	systemctl daemon-reload
 	systemctl enable vlmcsd
 	systemctl start vlmcsd
 	set_firewall
 	cd "${cur_dir}" || exit
    rm -rf vlmcsd
    clear
    echo
    echo "Install KMS Server success"
    echo
    echo "Enjoy it!"
 else
 	echo -e "${red}Error:${plain} Install KMS Server failed, please check it and try again."

 fi


}

# Uninstall KMS Server
uninstall_kms() {
    printf "Are you sure uninstall KMS Server? (y/n) "
    printf "\n"
    read -p "(Default: n):" answer
    [ -z "${answer}" ] && answer="n"
    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        systemctl status vlmcsd > /dev/null 2>&1
        if [ $? -eq 0 ]; then
           systemctl stop vlmcsd
           systemctl disable vlmcsd
        fi
        # delete kms server
        rm -f /usr/bin/vlmcsd-x64-musl-static
        rm -f /lib/systemd/system/vlmcsd.service
        rm -f /var/log/vlmcsd.log
        rm -f /var/run/vlmcsd.pid
        echo "KMS Server uninstall success"
    else
        echo
        echo "Uninstall cancelled, nothing to do..."
        echo
    fi
}


install_kms() {
    install_main 2>&1 | tee "${cur_dir}"/install_kms.log
}

# Initialization step
action=$1
[ -z "$1" ] && action=install
case "$action" in
    install|uninstall)
        ${action}_kms
        ;;
    *)
        echo "Arguments error! [${action}]"
        echo "Usage: $(basename $0) [install|uninstall]"
        ;;
esac