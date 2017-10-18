#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $TESTDIR/../script/test.sh

KON_SERVERS=swe:east:172.17.4.101,swe:west:172.17.4.102,\
swe:north:172.17.4.103,us:east:172.17.4.104

test::cluster::start () {
    source $SCRIPTDIR/common.sh
    source $SCRIPTDIR/config.sh
    source $SCRIPTDIR/pki.sh
    source $SCRIPTDIR/consul.sh
    source $SCRIPTDIR/cluster.sh

    active_config=$(common::dev_null)

    assert "start" "$(cluster::start)" ""
}

(test::cluster::start)