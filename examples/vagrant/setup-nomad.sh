#!/bin/bash

echo "This scripts setup Nomad and Consul on all nodes"

trap 'exit 1' ERR

echo "foo"

bootstrap_cmd="\
sudo mkdir -p /opt/bin \
&& sudo curl -s -o /opt/bin/kon https://raw.githubusercontent.com/TheNatureOfSoftware/kubernetes-on-nomad/master/kon \
&& sudo chmod a+x /opt/bin/kon \
&& sudo mkdir /etc/kon \
&& sudo cp /example/kon.conf /etc/kon/ \
&& sudo kon consul install \
&& sudo kon --interface eth1 consul start bootstrap \
&& sudo kon install nomad \
&& sudo kon install kube"

echo "bar"

node_cmd="\
sudo mkdir -p /opt/bin \
&& sudo curl -s -o /opt/bin/kon https://raw.githubusercontent.com/TheNatureOfSoftware/kubernetes-on-nomad/master/kon \
&& sudo chmod a+x /opt/bin/kon \
&& sudo mkdir /etc/kon \
&& sudo cp /example/kon.conf /etc/kon/ \
&& sudo kon consul install \
&& sudo kon --bootstrap 172.17.8.101 --interface eth1 consul start  \
&& sudo kon install nomad \
&& sudo kon install kube"

kubernetes_cmd="\
sudo kon generate all \
&& sudo kon start etcd"

vagrant ssh -c "$(printf "%s" "$bootstrap_cmd")" core-01

for i in `seq 2 6`; do
    (vagrant ssh -c "$(printf "%s" "$node_cmd")" core-0$i)
done

vagrant ssh -c "$(printf "%s" "$kubernetes_cmd")" core-01