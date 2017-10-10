#!/bin/bash

SCRIPTDIR=$TESTDIR/../script
KON_LOG_FILE=$TESTDIR/test.log
NO_LOG=true

assert () {
    if [ ! "$2" == "$3" ]; then
        printf "%s\n\t%s\n\t%s\n" "Test failed in: $1" "actual: [$2]" "expected: [$3]"
    fi
}