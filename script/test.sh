#!/bin/bash

SCRIPTDIR=$TESTDIR/../script
KON_LOG_FILE=$TESTDIR/test.log
NO_LOG=true
_test_="_"
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

assert () {
    test_description=$1
    if [ $test_name ]; then test_description="$test_name-$1"; fi
    if [ ! "$2" == "$3" ]; then
        printf "Test failed in: %s\n\tactual: [%s]\n\texpected: [%s]\n" "$test_description" "$2" "$3"
    fi
}

test::ip_addr_1 () {
    echo "192.168.100.101"
}

test::ip_addr_2 () {
    echo "192.168.100.101"
}