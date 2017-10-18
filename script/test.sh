#!/bin/bash

SCRIPTDIR=$TESTDIR/../script
KON_LOG_FILE=$TESTDIR/test.log
NO_LOG=true
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

assert () {
    test_description=$1
    if [ $test_name ]; then test_description="$test_name-$1"; fi
    if [ ! "$2" == "$3" ]; then
        printf "%s\n\t%s\n\t%s\n" "Test failed in: $test_description" "actual: [$2]" "expected: [$3]"
    fi
}