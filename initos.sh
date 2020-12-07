#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

echo 'A1234567b@2020'| passwd --stdin root

yum install git -y

cd /opt


[Unit]
Description=traffic
After=rc-local.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt
ExecStart=/usr/bin/python 1000G.py
Restart=always

[Install]
WantedBy=multi-user.target
