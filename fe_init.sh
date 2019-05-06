#!/bin/bash

#We'll hardcode to use DataPlane interface as default GW, instead of one configured via cloud-init
#ip l set dev ens33 up
#route delete default
#dhclient ens33

# Install software
apt -y update
apt -y install nginx

touch /etc/nginx/sites-available/app
cat << EOF > /etc/nginx/sites-available/app
server {
  listen 80;

  location / {
      proxy_pass http://10.10.6.20:8080/;
  }
}
EOF
ln -s /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
rm /etc/nginx/sites-enabled/default
systemctl restart nginx