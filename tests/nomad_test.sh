#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $TESTDIR/../script/test.sh
test_name="test::nomad::"

test::nomad::client_config () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh
    source $SCRIPTDIR/pki.sh
    source $SCRIPTDIR/nomad.sh

    ETCD_INITIAL_CLUSTER=node1=http://192.168.0.101:2380,node2=http://192.168.0.102:2380
    KON_MINIONS=node1=http://192.168.0.101:2380,http://192.168.0.103:2380
    
    nomad_advertise_ip=192.168.0.101
    nomad::client_config /dev/null
    assert "client_config_both_etcd_and_kubelet" "$_test_" "etcd,kubelet"

    nomad_advertise_ip=192.168.0.102
    nomad::client_config /dev/null
    assert "client_config_only_etcd" "$_test_" "etcd"

    nomad_advertise_ip=192.168.0.103
    nomad::client_config /dev/null
    assert "client_config_only_kubelet" "$_test_" "kubelet"
}

test::nomad::servers_config () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh
    source $SCRIPTDIR/nomad.sh

    servers="swe:east:node1:192.168.0.101, swe:east:node2:192.168.0.102"
    NO_LOG=false
    unset KON_SERVERS

    # No argument, should fail
    out="$(nomad::servers_config)"
    
    assert "servers_config" "${out:28}" "KON_SERVERS is not set, is KON_CONFIG loaded?"

    NO_LOG=true

    # Servers as $1
    assert "servers_config" "$(nomad::servers_config "$servers")" '["192.168.0.101","192.168.0.102"]'
    
    # KON_SERVERS set 
    KON_SERVERS=$servers
    assert "servers_config" "$(nomad::servers_config)" '["192.168.0.101","192.168.0.102"]'
}

(test::nomad::client_config)
(test::nomad::servers_config)