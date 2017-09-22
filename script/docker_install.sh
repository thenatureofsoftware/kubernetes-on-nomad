#!/bin/bash

docker::install () {
    log "Installing Docker..."
    apt-get -y install apt-transport-https ca-certificates curl software-properties-common > /dev/null 2>&1
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - > /dev/null 2>&1
    apt-key fingerprint 0EBFCD88 > /dev/null 2>&1
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /dev/null 2>&1
    apt-get update > /dev/null 2>&1
    apt-get install -y docker-ce > /dev/null 2>&1
    log "Docker version:\n$(docker version)"
    log "Done installing Docker"
}