#!/bin/bash

kubernetes::install () {
    info "installing Kubernetes components ..."
    kubernetes::install_by_download
    info "done installing Kubernetes components"
}

kubernetes::install_by_download () {

    mkdir -p /etc/kubernetes/manifests
    for kube_component in kubeadm kubectl kubelet kube-apiserver kube-scheduler kube-controller-manager; do
        if [ ! $(common::which $kube_component) ]; then
            
            local version=""
            if [ "$kube_component" == "kubeadm" ]; then
                version=$KUBEADM_VERSION
            else
                version=$K8S_VERSION
            fi

            kubernetes::download_and_install "$kube_component" "$version"
            common::fail_on_error "failed to install $kube_component"
        else
            info "$kube_component already installed"
        fi
    done

    
    if [ ! -f "/opt/cni/bin/loopback" ]; then
        if [ "$CNI_VERSION" == "" ]; then fail "CNI_VERSION is not set, is KON_CONFIG loaded?"; fi
        info "installing cni plugins..."
        info "$CNI_VERSION"
        mkdir -p /opt/cni/bin
        curl -sL https://github.com/containernetworking/plugins/releases/download/$CNI_VERSION/cni-plugins-amd64-$CNI_VERSION.tgz | tar zxv -C /opt/cni/bin > "$(common::dev_null)" 2>&1
        common::fail_on_error "failed to install cni plugins"
    else
        info "cni plugins already installed"
    fi
}

kubernetes::install_by_apt () {
    apt-get update > "$(common::dev_null)" 2>&1
    apt-get install -y apt-transport-https > "$(common::dev_null)" 2>&1
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - > "$(common::dev_null)" 2>&1
    cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
    deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
    local k8s_version=$(echo $K8S_VERSION | sed 's/v//g')-00
    apt-get update > "$(common::dev_null)" 2>&1
    apt-get install -y kubelet=$k8s_version kube-apiserver=$k8s_version > "$(common::dev_null)" 2>&1
    kubelet::reset
}

kubernetes::download_and_install() {
    if [ "$1" == "" ] || [ "$2" == "" ]; then
        fail "both component and version is required, got component:$2 and version:$1"
    fi

    info "downloading and installing: $1 version: $2"
    wget --quiet https://storage.googleapis.com/kubernetes-release/release/$2/bin/linux/amd64/$1
    chmod a+x $1
    mv $1 $BINDIR
    info "done installing $1"
}