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
    
    if [ "$KON_ETCD_SERVERS" == "" ]; then
        error "KON_ETCD_SERVERS is not set"
        exit 1
    fi

    # Put etcd configuration in Consul.
    consul::put $etcdServersKey "$(etcd::get_etcd_servers)"
    consul::put $etcdInitialClusterKey "$(etcd::get_etcd_initial_cluster)"
    consul::put $etcdInitialClusterTokenKey "$ETCD_INITIAL_CLUSTER_TOKEN"

    currentState=$(consul::get $etcdStateKey)
    if [ ! "$currentState" == $STARTED ] && [ ! "$currentState" == $RUNNING ]; then
        consul::put $etcdStateKey $CONFIGURED
    fi
}

###############################################################################
# Returns etcd servers 
###############################################################################
etcd::get_etcd_servers () {
    etcd_servers=()
    for ip in ${!config_etcd_servers[@]}; do
        etcd_servers+=(https://$ip:2379)
    done
    echo $(common::join_by , ${etcd_servers[@]})
}

###############################################################################
# Returns etcd initial cluster 
###############################################################################
etcd::get_etcd_initial_cluster () {
    etcd_servers=()
    for ip in ${!config_etcd_servers[@]}; do
        host=$(config::get_host $ip)
        etcd_servers+=($host=https://$ip:2380)
    done
    echo $(common::join_by , ${etcd_servers[@]})
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
