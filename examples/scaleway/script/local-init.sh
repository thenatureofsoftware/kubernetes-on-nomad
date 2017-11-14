#!/bin/bash
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ID_RSA_FILE="$BASEDIR/../kon_id_rsa"

if [ ! -f "$ID_RSA_FILE" ]; then
    ssh-keygen -q -t rsa -b 4096 -C "admin@kon" -N "" -f $ID_RSA_FILE
fi

