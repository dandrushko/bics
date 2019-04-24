#!/bin/bash

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