#!/bin/bash

echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin"' > /etc/environment

git clone https://github.com/TheNatureOfSoftware/tinc-net.git
tinc-net/setup-gw.sh jumpbox eth0 192.168.1.254

mkdir -p /opt/bin
curl -o /opt/bin/kon -sSL https://goo.gl/2RRdFu
chmod +x /usr/local/bin/kon

apt-get update
apt-get install -y jq unzip dnsutils bmon
