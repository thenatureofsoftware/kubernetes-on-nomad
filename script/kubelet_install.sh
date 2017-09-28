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
    apt-get install -y kubelet > /dev/null 2>&1
    wget --quiet https://storage.googleapis.com/kubernetes-release/release/$KUBEADM_VERSION/bin/linux/amd64/kubeadm
    chmod a+x kubeadm
    mv kubeadm $BINDIR

    log "$(kubelet --version)"
    log "$(kubeadm version)"
    log "Done installing Kubernetes components"
}