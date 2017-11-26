#!/bin/bash

echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin"' > /etc/environment

uname -a > ~/uname.out

apt-get update
apt-get install -y unzip jq dnsutils

systemctl stop docker
echo "DOCKER_OPTS='-H unix:///var/run/docker.sock --storage-driver overlay2 --label provider=scaleway --mtu=1500'" > /etc/default/docker
rm -rf /var/lib/docker*
systemctl start docker

