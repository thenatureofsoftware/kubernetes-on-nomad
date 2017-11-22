#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $TESTDIR/../script/test.sh
test_name="test::config::"

KON_BOOTSTRAP_SERVER="172.17.4.101"
KON_SERVERS=swe:east:core-01:172.17.4.101,swe:west:core-02:172.17.4.102,swe:north:core-03:172.17.4.103,us:east::172.17.4.104

KON_MINIONS=swe:east:core-05:172.17.4.105,swe:west:core-06:172.17.4.106,swe:north:core-07:172.17.4.107,us:east::172.17.4.108

test::config::get_dc () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh

    config::nodes

    assert "get_dc_east" "$(config::get_dc "172.17.4.101")" "east"
    assert "get_dc_west" "$(config::get_dc "172.17.4.102")" "west"
    assert "get_dc_north" "$(config::get_dc "172.17.4.103")" "north"
    assert "get_dc_wrong_ip" "$(config::get_dc "192.168.100.101")" ""
}

test::config::get_region () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh

    config::nodes

    assert "get_region_swe" "$(config::get_region "172.17.4.101")" "swe"
    assert "get_region_us" "$(config::get_region "172.17.4.104")" "us"
    assert "get_region_wrong_ip" "$(config::get_region "192.168.100.101")" ""
}

test::config::get_host () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh

    config::nodes

    assert "get_host_core-01" "$(config::get_host "172.17.4.101")" "core-01"
    assert "get_host_core-02" "$(config::get_host "172.17.4.102")" "core-02"
    assert "get_host_empty" "$(config::get_host "172.17.4.104")" ""
    assert "get_host_wrong_ip" "$(config::get_host "192.168.100.101")" ""
}

test::config::nodes () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh

    config::nodes

    assert "nodes" "$config_bootstrap_server" "$KON_BOOTSTRAP_SERVER"
    assert "nodes" "${config_nodes["172.17.4.101"]}" "core-01:swe:east"
    assert "nodes_num" "${#config_nodes[@]}" "8"
}

test::config::regions () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh

    config::nodes
    config::regions

    assert "regions_num" "${#config_regions[@]}" "2"
    assert "regions_swe" "${config_regions[swe]}" "east west north"
    assert "regions_swe" "${config_regions[us]}" "east"
}

test::config::check_unique_dc  () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh

    config::nodes
    config::regions

    NO_LOG=false
    out=$(config::check_unique_dc)
    assert "check_unique_dc " "${out:28}" "found multiple datacenters named: east in different regions, datacenter names must be globaly unique"
}

test::config::configure_job () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh

    config::nodes
    config::regions

    actula_region=$(cat $TESTDIR/../nomad/job/etcd.nomad | config::configure_job swe | sed '2q;d' | sed 's/ //g')
    actula_dc=$(cat $TESTDIR/../nomad/job/etcd.nomad | config::configure_job swe | sed '3q;d' | sed 's/ //g')
    assert "config::configure_job" "$actula_region" "region=\"swe\""
    assert "configure_job" "$actula_dc" "datacenters=[\"east\",\"west\",\"north\"]"
}

test::config::node_all () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh

    assert "node_region" "$(config::node_region "swe:east:node1:192.168.100.101")" "swe"
    assert "node_dc" "$(config::node_dc "swe:east:node1:192.168.100.101")" "east"
    assert "node_hostname" "$(config::node_hostname "swe:east:node1:192.168.100.101")" "node1"
    assert "node_ip" "$(config::node_ip "swe:east:node1:192.168.100.101")" "192.168.100.101"
    assert "node_meta" "$(config::node_meta "swe:east:node1:192.168.100.101")" "node1:swe:east"
}


(test::config::get_region)
(test::config::get_dc)
(test::config::get_host)
(test::config::nodes)
(test::config::regions)
(test::config::check_unique_dc)
(test::config::configure_job)
(test::config::node_all)