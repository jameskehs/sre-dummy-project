#!/bin/bash
sudo apt update
sudo apt-get install -y curl

curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs
node -v

sudo apt install git -y
git clone https://github.com/jameskehs/sre-dummy-project.git /opt/sre-dummy-project

cd /opt/sre-dummy-project/app
npm install

cat > /etc/systemd/system/sre-dummy-app.service <<EOF
[Unit]
Description=SRE Dummy App Service

[Install]
WantedBy=multi-user.target

[Service]
WorkingDirectory=/opt/sre-dummy-project/app
ExecStart=/usr/bin/node --env-file-if-exists=.env /opt/sre-dummy-project/app/server.js
Restart=always

EOF

sudo systemctl daemon-reload
sudo systemctl enable --now sre-dummy-app.service



