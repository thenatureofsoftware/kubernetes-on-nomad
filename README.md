# kubernetes-on-nomad

## What

Kubernetes-On-Nomad `kon` is a tool for simplifying running [Kubernetes](https://kubernetes.io/) on [Nomad](https://www.nomadproject.io/) using [Consul](https://www.consul.io/) (Vault comming soon) for storing all Kubernetes configuration.

## Why

* All etcd and kubernetes configuration and certificates stored in Consul (Vault comming soon)
* Simple handling of Kubernetes infrastructure and control plane
* HA? There is no single master. Nomad handles the Kubernetes Control plane.
* Easy to set up a Kubernetes cluster (uses kubeadm under the hood)

## How

```
$ # Generate a config file and edit it for your environment
$ kon generate init
$ # Run this on the bootstrap server
$ kon consul install && kon consul start bootstrap
$ kon nomad install && kon nomad start
$ # Generates all certificates and kubeconfigs and stores it in Consul
$ kon generate all
```
and
```
$ # Run this on all the other nodes
$ kon kubernetes install
$ kon consul install && kon --bootstrapserver <IP-address> consul start 
$ kon nomad install && kon nomad start
```

next on any node:
```
$ # Start etcd
$ kon etcd start
$ # Start Kubernetes control plane
$ kon start control-plane
$ kon start kubelet
$ kon start kube-proxy
```

setup `kubectl` and install Kubernetes networking
```
$ kon setup kubectl
$ kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
```



see the [examples](./examples)


