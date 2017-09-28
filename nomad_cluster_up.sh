#!/bin/bash

DEBIAN_FRONTEND=noninteractive
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTDIR=$BASEDIR/script
BINDIR=${BINDIR:=/usr/bin}

# Consul
CONSUL_VERSION=${CONSUL_VERSION:=0.9.3}
CONSUL_DATADIR=${CONSUL_DATADIR:=/var/lib/consul}
CONSUL_CONFIGDIR=${CONSUL_CONFIGDIR:=/etc/consul}

# Vault (not used)
VAULT_VERSION=${VAULT_VERSION:=0.8.3}
VAULT_CONFIGDIR=${VAULT_CONFIGDIR:=/etc/vault}
#VAULT_DATADIR=${VAULT_DATADIR:=/var/lib/vault}

# Nomad
NOMAD_VERSION=${NOMAD_VERSION:=0.6.3}
NOMAD_DATADIR=${NOMAD_DATADIR:=/var/lib/consul}
NOMAD_CONFIGDIR=${NOMAD_CONFIGDIR:=/etc/consul}
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:=9B4T6UOOQNQRRHSAWVPY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:=HtcN68VAx0Ty5UslYokP6UA3OBfWVMFDZX6aJIfh}

# Kubernetes
KUBEADM_VERSION=${KUBEADM_VERSION:=v1.9.0-alpha.1}

source $BASEDIR/setup.env
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/common_install.sh
source $SCRIPTDIR/docker_install.sh
source $SCRIPTDIR/consul_install.sh
source $SCRIPTDIR/vault_install.sh
source $SCRIPTDIR/nomad_install.sh
source $SCRIPTDIR/kubelet_install.sh
source $SCRIPTDIR/minio_install.sh
source $SCRIPTDIR/cfssl_install.sh

log "step 1 - Preparing node by installing consul, nomad and kubernetes binaries"
log "Consul version: $CONSUL_VERSION"
log "Vault version: $VAULT_VERSION"
log "Nomad version: $NOMAD_VERSION"

common::check_root
common::install
cfssl::install

docker::install

consul::install
consul::enable_service

vault::install
vault::enable_service

nomad::install
nomad::enable_service

kubelet::install
consul::enable_dns
