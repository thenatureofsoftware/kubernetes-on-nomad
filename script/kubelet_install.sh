#!/bin/bash

kubelet::install () {
    log "Installing kubelet and kubeadm"
    apt-get update > /dev/null 2>&1
    apt-get install -y apt-transport-https > /dev/null 2>&1
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
    deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
    apt-get update > /dev/null 2>&1
    apt-get install -y kubelet kubeadm > /dev/null 2>&1
    log "$(kubelet --version)"
    log "$(kubeadm version)"
    log "Done installing Kubernetes components"
}