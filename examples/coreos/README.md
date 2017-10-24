# Setting up Kubernetes On Nomad using CoreOS (Vagrant)

This example shows how to setup **Kubernetes-On-Nomad** on four CoreOS Vagrant servers.
You need Vagrant installed and it's only been tested on VirtulaBox.

The example uses the new `cluster` command.

You need `bash >= 4` to run `kon`. If you're on OSX you can install a newer version of
`bash` using [Homebrew](https://brew.sh/) and `brew install bash`.

First you need to clone the project:
```
$ git clone https://github.com/TheNatureOfSoftware/kubernetes-on-nomad.git
$ cd kubernetes-on-arm/examples/coreos
```

Kubernetes-On-Nomad (`kon`) uses a configuration file `kon.conf` for setting up a cluster.
You can generate a sample configuration file by running:
```
$ kon generate init
```

For this example there's already a [kon.conf](./kon.conf) configuration file.

The configuration tells `kon` which nodes should be used as Nomad and Consul servers:
```
# This a comma separated list of servers <region>:<datacenter>:<hostname>:<IP address>
KON_SERVERS=swe:east:core-01:172.17.8.101
```
and witch servers should be used as `etcd` servers:
```
ETCD_SERVERS=http://172.17.8.101:2379
ETCD_INITIAL_CLUSTER=core-01=http://172.17.8.101:2380
ETCD_INITIAL_CLUSTER_TOKEN=etcd-initial-token-dc1
```

The configuration also lists all nodes that will be used as Kubernetes nodes.
Kubernetes nodes are called **minions**, to separate them from Nomad nodes.
There are three `minions` in this example. The format is the same as for `KON_SERVERS`.
```
KON_MINIONS=swe:east:core-02:172.17.8.102,swe:east:core-03:172.17.8.103,swe:east:core-04:172.17.8.104
```

First we need to boot up all our servers. This step and the configuration `KON_VAGRANT_SSH=true` in `kon.conf` is the only Vagrant specific about this example.

Run:
```
$ vagrant up
```

When all servers are up and running it's time to start our Nomad cluster.

Make sure your in the right spot and use `kon` to start the cluster:
```
$ pwd
.../kubernetes-on-nomad/examples/coreos
$ bash ../../kon.sh --config ./kon.conf cluster apply 
```

When the `cluster apply`-command is done, login on any node and check the state.

First login:
```
$ vagrant ssh core-03
core@core-03 ~ $ # Switch to root
core@core-03 ~ $ sudo -u root -i
```
and check the cluster state using the `view state`-command:
```
core-03 ~ # eval $(kon --quiet nomad env)
core-03 ~ # kon --quiet view state
Components                              State
-----------------------                 ----------
certificates                            
config                                  OK
consul                                  Running
etcd                                    NotConfigured
kube-apiserver                          
kube-controller-manager                 
kube-proxy                              
kube-scheduler                          
kubeconfig                              
kubelet                                 
nomad                                   Running
```
As you can see Consul and Nomad are running and `kon.conf` has been stored in Consul. All `DNS` queries on the host are delegated to Consul. You can test this by issuing the following:
```
core-03 ~ # dig +short google.com
172.217.18.142
core-03 ~ # dig +short nomad.service.east.consul
172.17.8.101
``` 

We now have a Nomad cluster with Consul. Before we can start Kubernetes we
need to configure and start `etcd`:
```
core-03 ~ # kon -yes etcd config && kon etcd start && kon --quiet view state
```
```
Components                              State
-----------------------                 ----------
certificates                            
config                                  OK
consul                                  Running
etcd                                    Running
kube-apiserver                          Stopped
kube-controller-manager                 Stopped
kube-proxy                              Stopped
kube-scheduler                          Stopped
kubeconfig                              
kubelet                                 Stopped
kubernetes                              Stopped
nomad                                   Running
```

The last step is to configure and start Kubernetes:
```
core-03 ~ # kon kubernetes config && kon kubernetes start && watch kon --quiet view state
```
```
Every 2.0s: kon --quiet view state                                                                                                               Tue Oct 24 14:05:19 2017

Components                              State
-----------------------                 ----------
certificates                            OK
config                                  OK
consul                                  Running
etcd                                    Running
kube-apiserver                          Running
kube-controller-manager                 Running
kube-proxy                              Running
kube-scheduler                          Running
kubeconfig                              OK
kubelet                                 Running
kubernetes                              Running
kubernetes/minion/core-02               Ready
kubernetes/minion/core-03               Ready
kubernetes/minion/core-04               Ready
nomad                                   Running
```

You now have a Kubernetes cluster, up and running on Nomad, to play around with.
I encourage you to try out what happens if you kill the `apiserver`, or any other
component, in the Kubernetes control plane. Or why not shutdown one of the servers (except `core-01`)?
