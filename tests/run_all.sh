#!/bin/bash

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $TESTDIR/common_test.sh
source $TESTDIR/config_test.sh
source $TESTDIR/consul_test.sh
source $TESTDIR/nomad_test.sh
source $TESTDIR/ssh_test.sh
source $TESTDIR/pki_test.sh
source $TESTDIR/cluster_test.sh
