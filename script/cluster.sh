#!/bin/bash

###############################################################################
# Variables
###############################################################################

cluster::start () {

    # Verify encryption keys.
    cluster::verify_encryption_keys

    for node in ${!config_nodes[@]}
    do
        
        KON_SSH_HOST="$(config::get_host $node)"
        if [ "$KON_SSH_HOST" == "" ]; then
            KON_SSH_HOST="$node"
        fi
        info "$KON_SSH_HOST will be used as node"
        cluster::start_node
    done
}

###############################################################################
# Starts the bootstrap server.
###############################################################################
cluster::start_node () {
    info "starting node $KON_SSH_HOST ..."
    
    ssh::ping > "$(common::dev_null)" 2>&1
    if [ $? -gt 0 ]; then fail "failed to connect to node: $KON_SSH_HOST and user: $KON_SSH_USER"; fi

    # Copy config first.
    ssh::copy

    ssh::install_kon > "$(common::dev_null)" 2>&1

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
