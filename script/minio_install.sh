#!/bin/bash

sudo wget --quiet https://dl.minio.io/client/mc/release/linux-amd64/mc
sudo chmod a+x mc

sudo mv mc $BINDIR/