# kubernetes-on-nomad

## Why

* All etcd and kubernetes configuration and certificates stored in Consul (Vault comming soon)
* Simple handling of Kubernetes infrastructure and control plane
* HA?
* Easy to set up a Kubernetes cluster (uses kubeadm under the hood)

## How

* Nomad cluster with Consul
* All DNS lookup delegated to Consul (and recursors) on all nodes:
```shell
root@node1:~# dig kubernetes.service.dc1.consul

; <<>> DiG 9.10.3-P4-Ubuntu <<>> kubernetes.service.dc1.consul
...
;; QUESTION SECTION:
;kubernetes.service.dc1.consul.	IN	A

;; ANSWER SECTION:
kubernetes.service.dc1.consul. 0 IN	A	172.17.4.102

;; Query time: 0 msec
;; SERVER: 127.0.0.1#53(127.0.0.1)
;; WHEN: Mon Oct 02 21:52:36 UTC 2017
;; MSG SIZE  rcvd: 74
```


