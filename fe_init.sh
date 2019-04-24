#!/bin/bash

apt -y update
apt install nginx

cat << EOF > /etc/nginx/sites-available/app.config

EOF