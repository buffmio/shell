

[Unit]
Description=test deamon
After=rc-local.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/home
ExecStart=/usr/bin/python test.py
Restart=always

[Install]
WantedBy=multi-user.target
