#!/bin/bash

echo "This scripts setup Nomad and Consul on all nodes"

trap 'exit 1' ERR

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

(vagrant destroy -f)
(vagrant up --parallel --destroy-on-error)

echo "Starting provisioning bootstrap node core-01"
(vagrant ssh -c "$(printf "%s" "$bootstrap_cmd")" core-01 -- -T)

for i in `seq 2 6`; do
    (
        echo "Starting provisioning for node core-0$i"
        vagrant ssh -c "$(printf "%s" "$node_cmd")" core-0$i -- -T &
    ) &
done
sleep 1
echo "Waiting for nodes come to become ready..."
wait

echo "Nodes are done"
echo "Entering grace period..."
sleep 30
echo "Grace period over"

echo "Generating all configuration for Kubernetes and starting etcd."
(vagrant ssh -c "$(printf "%s" "$kubernetes_cmd")" core-01 -- -T)

echo "To view etcd status run: -- vagrant ssh -c 'watch nomad job status etcd' core-01"