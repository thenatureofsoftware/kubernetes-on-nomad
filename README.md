# kubernetes-on-nomad

## What

Kubernetes-On-Nomad `kon` is a tool for simplifying running [Kubernetes](https://kubernetes.io/) on [Nomad](https://www.nomadproject.io/) using [Consul](https://www.consul.io/) (Vault comming soon) for storing all Kubernetes configuration.

It's not involved during runtime but helps you setup Nomad, Consul and Kubernetes together.

## Why

* All etcd and kubernetes configuration and certificates stored in Consul (Vault coming soon)
* Simple handling of Kubernetes infrastructure and control plane
* HA out of the box, there is no single master as long as you have enough nodes. Nomad handles the Kubernetes Control plane.
* Easy to set up a Kubernetes cluster (uses kubeadm under the hood)

## How

Generate a sample `kon.conf` file:
```
$ kon generate init
```

Edit `kon.conf` and add all your machines. Then run `cluster start` on any machine that can do `ssh` password-less:
```
$ kon --config ./kon.conf cluster start
```

Then login on any node and run:
```
core-01 ~ # kon generate all
core-01 ~ # kon etcd start
core-01 ~ # kon kubernetes start
core-01 ~ # kon setup kubectl
core-01 ~ # kon addon dns
core-01 ~ # kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
```

see the [CoreOS example](./examples/coreos)


