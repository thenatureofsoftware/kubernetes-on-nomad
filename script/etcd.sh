#!/bin/bash

###############################################################################
# Validates etcd configuration and puts it in Consul.
###############################################################################
etcd::config () {

    for key in  $etcdServersKey $etcdInitialClusterKey $etcdInitialClusterTokenKey $etcdServiceKey/cert $etcdServiceKey/key; do
        if [ "$(consul::has_key $key)" ]; then
            fail "etcd is already configured, please reset first";
        fi    
    done

    if [ ! -f "$KON_PKI_DIR/ca.key" ]; then
        pki::setup_node_certificates
        ls -la $KON_PKI_DIR
    fi

    # install cfssl if it's missing
    common_install::cfssl

    pki::generate_etcd_service_cert
    
    if [ "$ETCD_SERVERS" == "" ]; then
        error "ETCD_SERVERS is not set"
        exit 1
    fi

    if [ "$ETCD_INITIAL_CLUSTER" == "" ]; then
        error "ETCD_INITIAL_CLUSTER is not set"
        exit 1
    fi

    if [ "$ETCD_INITIAL_CLUSTER_TOKEN" == "" ]; then
        error "ETCD_INITIAL_CLUSTER_TOKEN is not set"
        exit 1
    fi

    # Put etcd configuration in Consul.
    consul::put $etcdServersKey "$ETCD_SERVERS"
    consul::put $etcdInitialClusterKey "$ETCD_INITIAL_CLUSTER"
    consul::put $etcdInitialClusterTokenKey "$ETCD_INITIAL_CLUSTER_TOKEN"

    currentState=$(consul::get $etcdStateKey)
    if [ ! "$currentState" == $STARTED ] && [ ! "$currentState" == $RUNNING ]; then
        consul::put $etcdStateKey $CONFIGURED
    fi
}

###############################################################################
# Starts etcd 
###############################################################################
etcd::start () {
    for key in  $etcdServersKey $etcdInitialClusterKey $etcdInitialClusterTokenKey $etcdServiceKey/cert $etcdServiceKey/key; do
        if [ ! "$(consul::has_key "$key")" ]; then
            consul::fail_if_missing_key $key "$key is missing, configure etcd first"
        fi
    done
    
    info "starting etcd ..."
    nomad::run_job "etcd"
    info "etcd started"
}

###############################################################################
# Stops etcd 
###############################################################################
etcd::stop () {
    info "stopping etcd ..."
    nomad::stop_job "etcd"
    info "etcd stopped"
}

###############################################################################
# Stopps and removes etcd.
###############################################################################
etcd::reset () {
    nomad::stop_job "etcd"
    consul::delete_all $etcdKey
    consul::put $etcdStateKey "$NOT_CONFIGURED"
}
