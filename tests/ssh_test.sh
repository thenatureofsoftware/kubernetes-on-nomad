#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $TESTDIR/../script/test.sh

KON_SERVERS=swe:east:172.17.4.101,swe:west:172.17.4.102,\
swe:north:172.17.4.103,us:east:172.17.4.104

test::ssh::setup_node_bootstrap () {
    source $SCRIPTDIR/ssh.sh
    _test_=true

    assert "ssh::setup_node_bootstrap" "$(ssh::setup_node_bootstrap "encrypt")" "sudo kon --consul-encrypt encrypt setup node bootstrap"
}
(test::ssh::setup_node_bootstrap)