#!/bin/bash

###############################################################################
# Variables
###############################################################################

cluster::apply () {

    KON_PKI_DIR=$PWD/.pki

    mkdir -p $KON_PKI_DIR/

    # Verify encryption keys.
    cluster::verify_encryption_keys

    # Generate CA
    pki::generate_ca

    for node in ${!config_nodes[@]}
    do  
        pki::generate_client_cert $node      
        pki::generate_consul_cert $node
        pki::generate_nomad_cert $node

        KON_SSH_HOST="$(config::get_host $node)"
        if [ "$KON_SSH_HOST" == "" ]; then
            KON_SSH_HOST="$node"
        fi
        info "$KON_SSH_HOST will be used as node"
        cluster::start_node $node
    done
}

###############################################################################
# Starts the bootstrap server.
###############################################################################
cluster::start_node () {
    node=$1
    info "starting node $node $KON_SSH_HOST ..."
    
    ssh::ping > "$(common::dev_null)" 2>&1
    if [ $? -gt 0 ]; then fail "failed to connect to node: $KON_SSH_HOST and user: $KON_SSH_USER"; fi

    # Copy config first.
    ssh::copy $node

    #ssh::install_kon > "$(common::dev_null)" 2>&1
    ssh::install_kon

    ssh::setup_node
}

###############################################################################
# Verifies that there is a valid Consul and Nomad encryption key, else fails.
###############################################################################
cluster::verify_encryption_keys () {
    info "verifying encryption keys for Consul and Nomad ..."
    for key_config in KON_CONSUL_ENCRYPTION_KEY KON_NOMAD_ENCRYPTION_KEY
    do
        key_is_configured=false
        if [ "${!key_config}" == "" ]; then
            eval ${key_config}="$(consul::generate_encryption_key)"
            key_is_configured=true
        fi

        if [ "$key_is_configured" == "true" ]; then
            cat <<EOF >> $active_config

# Added by 'kon cluster start'-command
${key_config}=${!key_config}
EOF
            info "$key_config written to $active_config"
        fi
    done
    info "encryption keys are OK"
}
