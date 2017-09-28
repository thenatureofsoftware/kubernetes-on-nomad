#!/bin/bash

kubelet::install () {
    log "Installing kubelet, kubectl and kubeadm ..."
    
    apt-get update > /dev/null 2>&1
    apt-get install -y apt-transport-https > /dev/null 2>&1
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
    deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
    apt-get update > /dev/null 2>&1
    apt-get install -y kubelet > /dev/null 2>&1
    
    #kubelet::download_and_install "kubelet" "$K8S_VERSION"
    kubelet::download_and_install "kubectl" "$K8S_VERSION"
    kubelet::download_and_install "kubeadm" "$KUBEADM_VERSION"
    kubelet::reset

    log "Done installing Kubernetes components"
}

kubelet::download_and_install() {
    info "Downloading and installing: $1 version: $2"
    wget --quiet https://storage.googleapis.com/kubernetes-release/release/$2/bin/linux/amd64/$1
    chmod a+x $1
    mv $1 $BINDIR
    info "Done installing $1"
}

kubelet::reset () {
    info "Calling kubeadm reset" "\n$(kubeadm reset)"
    log "Stopping kubelet.service"
    systemctl stop kubelet > /dev/null 2>&1
    log "Disable kubelet.service"
    systemctl disable kubelet > /dev/null 2>&1
    common::rm_all_running_containers
    rm -rf /var/lib/kubelet/* > /dev/null 2>&1
}