#!/bin/bash
wget --quiet -O cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
chmod a+x cfssl
mv cfssl $BINDIR