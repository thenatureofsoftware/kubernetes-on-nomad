#!/bin/bash

DEBIAN_FRONTEND=noninteractive
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTDIR=$BASEDIR/script
BINDIR=${BINDIR:=/usr/bin}
CONSUL_VERSION=${CONSUL_VERSION:=0.9.3}
CONSUL_DATADIR=${CONSUL_DATADIR:=/var/lib/consul}
CONSUL_CONFIGDIR=${CONSUL_CONFIGDIR:=/etc/consul}
VAULT_VERSION=${VAULT_VERSION:=0.8.3}
VAULT_CONFIGDIR=${VAULT_CONFIGDIR:=/etc/vault}
#VAULT_DATADIR=${VAULT_DATADIR:=/var/lib/vault}
NOMAD_VERSION=${NOMAD_VERSION:=0.6.3}
NOMAD_DATADIR=${NOMAD_DATADIR:=/var/lib/consul}
NOMAD_CONFIGDIR=${NOMAD_CONFIGDIR:=/etc/consul}
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:=9B4T6UOOQNQRRHSAWVPY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:=HtcN68VAx0Ty5UslYokP6UA3OBfWVMFDZX6aJIfh}


source $BASEDIR/setup.env
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/common_install.sh
source $SCRIPTDIR/docker_install.sh
source $SCRIPTDIR/consul_install.sh
source $SCRIPTDIR/vault_install.sh
source $SCRIPTDIR/nomad_install.sh
source $SCRIPTDIR/kubelet_install.sh
source $SCRIPTDIR/minio_install.sh

log "step 1 - Preparing node by installing consul, nomad and kubernetes binaries"
common::log ADVERTISE_IP=$ADVERTISE_IP
common::log CONSUL_VERSION=$CONSUL_VERSION
common::log CONSUL_DATADIR=$CONSUL_DATADIR
common::log CONSUL_CONFIGDIR=$CONSUL_CONFIGDIR
common::log NOMAD_VERSION=$NOMAD_VERSION
common::log NOMAD_DATADIR=$NOMAD_DATADIR
common::log NOMAD_CONFIGDIR=$NOMAD_CONFIGDIR
common::log BINDIR=$BINDIR

common::check_root
common::install

docker::install

consul::install
consul::enable_service

vault::install
vault::enable_service

nomad::install
nomad::enable_service

kubelet::install