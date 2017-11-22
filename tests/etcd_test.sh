#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $TESTDIR/../script/test.sh
source $TESTDIR/../script/common.sh
source $TESTDIR/../script/config.sh
test_name="test::etcd::"

KON_BOOTSTRAP_SERVER="172.17.4.101"
KON_ETCD_SERVERS=swe:east:core-01:172.17.4.101,swe:west:core-02:172.17.4.102,swe:north:core-03:172.17.4.103

test::etcd::get_etcd_servers () {
    source $TESTDIR/../script/etcd.sh
    config::nodes
    assert "get_etcd_servers" "$(etcd::get_etcd_servers)" "https://172.17.4.101:2379,https://172.17.4.103:2379,https://172.17.4.102:2379"
}

test::etcd::get_etcd_initial_cluster () {
    source $TESTDIR/../script/etcd.sh
    config::nodes
    assert "get_etcd_initial_cluster" "$(etcd::get_etcd_initial_cluster)" "core-01=https://172.17.4.101:2380,core-03=https://172.17.4.103:2380,core-02=https://172.17.4.102:2380"
}

(test::etcd::get_etcd_servers)
(test::etcd::get_etcd_initial_cluster)