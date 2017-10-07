#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTDIR=$TESTDIR/../script
KON_LOG_FILE=$TESTDIR/test.log
NO_LOG=true

assert () {
    if [ ! "$2" == "$3" ]; then
        printf "%s\n\t%s\n\t%s\n" "Test failed in: $1" "actual: [$2]" "expected: [$3]"
    fi
}

test::nomad::client_config () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/nomad.sh

    ETCD_INITIAL_CLUSTER=node1=http://192.168.0.101:2380,node2=http://192.168.0.102:2380
    KUBE_MINIONS=node1=http://192.168.0.101:2380,http://192.168.0.103:2380
    
    nomad_advertise_ip=192.168.0.101
    nomad::client_config /dev/null
    assert "nomad::client_config_both_etcd_and_kubelet" "$_test_" "etcd,kubelet"

    nomad_advertise_ip=192.168.0.102
    nomad::client_config /dev/null
    assert "nomad::client_config_only_etcd" "$_test_" "etcd"

    nomad_advertise_ip=192.168.0.103
    nomad::client_config /dev/null
    assert "nomad::client_config_only_kubelet" "$_test_" "kubelet"
}

(test::nomad::client_config)