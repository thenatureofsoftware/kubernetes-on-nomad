#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $TESTDIR/../script/test.sh
test_name="test::ssh::"

KON_SERVERS=swe:east:172.17.4.101,swe:west:172.17.4.102,\
swe:north:172.17.4.103,us:east:172.17.4.104

test::ssh::cmd () {
    source $SCRIPTDIR/ssh.sh

    assert "cmd_ssh" "$(ssh::cmd node1)" "ssh "
    
    KON_SSH_USER=root
    KON_SSH_HOST=node
    assert "cmd_ssh" "$(ssh::cmd)" "ssh root@node"

    KON_VAGRANT_SSH=true
    assert "cmd_vagrant" "$(ssh::cmd)" "vagrant ssh node"

    _test_=true
    assert "cmd_vagrant" "$(ssh::cmd)" "cat"
}
(test::ssh::cmd)