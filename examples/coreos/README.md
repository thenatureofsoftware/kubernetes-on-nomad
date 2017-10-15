# Setting up Kubernetes On Nomad using CoreOS (Vagrant)

This example shows how to setup **Kubernetes-On-Nomad** on four CoreOS Vagrant servers.
You need Vagrant installed and it's only been tested on VirtulaBox.

The example uses the new `cluster` command.

You need `bash >= 4` to run `kon`. If you're on OSX you can install a newer version of `bash` using [Homebrew](https://brew.sh/) and `brew install bash`.

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
In this example there's three `minions`. The format is the same as for `KON_SERVERS`.
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
$ bash ../../kon.sh --config ./kon.conf cluster start 
```

When the `cluster start`-command is done, login on any node and check the state.

First login:
```
$ vagrant ssh core-03
core@core-03 ~ $ # Switch to root
core@core-03 ~ $ sudo -u root -i
```
and check the cluster state using the `view state`-command:
```
core-03 ~ # kon --quiet view state
Components                              State
-----------------------                 ----------
certificates                            
config                                  OK
consul                                  Running
etcd                                    
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

We now have a Nomad cluster with Consul. Now it's time to setup Kubernetes.

Let's start with generating all certificates and configuration using the `generate all`-command, then view the state again:
```
core-03 ~ # kon --quiet generate all && kon --quiet view state
Components                              State
-----------------------                 ----------
certificates                            OK
config                                  OK
consul                                  Running
etcd                                    Configured
kube-apiserver                          
kube-controller-manager                 
kube-proxy                              OK
kube-scheduler                          
kubeconfig                              OK
kubelet                                 
nomad                                   Running
```
We can see that `certificates` and `kubeconfig` are `OK` and `etcd` is `Configured`.


Now start `etcd` using the `etcd start`-command and watch it enter the running state:
```
core-03 ~ # kon --quiet etcd start && watch kon --quiet view state  
```
```
Every 2.0s: kon --quiet view state                                                                                                                        Mon Oct 16 06:54:39 2017

Components                              State
-----------------------                 ----------
certificates                            OK
config                                  OK
consul                                  Running
etcd                                    Running
kube-apiserver
kube-controller-manager
kube-proxy                              OK
kube-scheduler
kubeconfig                              OK
kubelet
nomad                                   Running
```
You can verify that you have a `etcd` cluster up and running in Nomad by querying Consul:
```
core-03 ~ # dig +short etcd.service.east.consul
172.17.8.102
172.17.8.103
```

Now let's start Kubernetes using the `kubernetes start`-command and the `setup kubectl`-command:
```
core-03 ~ # kon --quiet kubernetes start && kon --quiet setup kubectl && watch kon --quiet view state
```
```
Every 2.0s: kon --quiet view state                                                                                                                        Mon Oct 16 07:01:34 2017

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
kubernetes/minion/core-02               NotReady
kubernetes/minion/core-03               NotReady
kubernetes/minion/core-04               NotReady
nomad                                   Running
```
As you can see Kubernetes and all `minions` are up and running. The `minion`:s state is `NotReady` and that's because we haven't installed any Kubernetes network.

You can use any CNI-network plugin but make sure to configure the right `POD_CLUSTER_CIDR` in `kon.conf`.

In this setup we're going to use [`weave`](https://weave.works).

Use `kubectl` to install [`weave`](https://weave.works) and at the same time install the Kubernetes DNS addon using the `addon dns`-command and finally view the state:
```
core-03 ~ # kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')" && kon --quiet addon dns && watch kon --quiet view state
```
```
Every 2.0s: kon --quiet view state                                                                                                                        Mon Oct 16 07:13:25 2017

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
component, in the Kubernetes control plane.

