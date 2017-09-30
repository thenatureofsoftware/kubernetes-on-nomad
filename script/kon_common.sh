#!/bin/bash

kon::generate_config_template () {
    cat <<EOF > $K8S_ON_NOMAD_CONFIG_FILE
#!/bin/bash

###############################################################################
# Kubernetes version
###############################################################################
K8S_VERSION=${K8S_VERSION:=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)}

###############################################################################
# List of comma separated addresses <scheme>://<ip>:<port>
###############################################################################
ETCD_SERVERS=http://127.0.0.1:2379

###############################################################################
# List of etcd initial cluster <name>=<scheme>://<ip>:<port>
###############################################################################
ETCD_INITIAL_CLUSTER=default=http://127.0.0.1:2380

###############################################################################
# Etcd initial cluster token
###############################################################################
ETCD_INITIAL_CLUSTER_TOKEN=etcd-initial-token-dc1

###############################################################################
# List of minions (kubernetes nodes). Must be nomad nodes with node_class
# containing kubelet. Exampel : node_class = "etcd,kubelet"
###############################################################################
KUBE_MINIONS=node1=192.168.0.1,node2=192.168.0.2,node3=192.168.0.3,\
node4=192.168.0.3

###############################################################################
# kube-apiserver advertise address
###############################################################################
KUBE_APISERVER=192.168.0.1
KUBE_APISERVER_PORT=6443
KUBE_APISERVER_EXTRA_SANS=kubernetes.service.dc1.consul,kubernetes.service.dc1,kubernetes.service
KUBE_APISERVER_ADDRESS=https://kubernetes.service.dc1.consul:6443

EOF
}