#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

Green="\033[32m"
Red="\033[31m"

#swapfile dir
file="/swapfile"
echo -e "请输入需要添加的swap，建议为内存的2倍！"
read -p "请输入swap数值:" swapsize

#create swapfile
echo "creating swapfile"

fallocate -l ${swapsize}G $file

if [ -f "$file" ]; then
    echo -e "${Green}swapfile Created successfully"
else
    echo -e "${Red}error:swapfile create failed" && exit 1
fi

chmod 600 $file

#configure swapfile
echo "configuring swapfile"

mkswap $file
swapon $file
echo "$file swap swap defaults 0 0" >>/etc/fstab

grep -q "swapfile" /etc/fstab

if [ %? -eq=0]; then
    echo -e "${Green}configured swapfile successfully"
else
    echo -e "${Red}error:configure swapfile failed"
fi
