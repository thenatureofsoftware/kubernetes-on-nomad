# Setting up Kubernetes On Nomad using CoreOS (Vagrant)

This example will show you how to setup Kubernetes On Nomad on four CoreOS Vagrant servers.
You need Vagrant installed and it's only been tested on VirtulaBox.

## TL;DR

I do recommend to follow the steps below, but if you're impatient you can bring up the cluster by running the following:
```
$ git clone https://github.com/TheNatureOfSoftware/kubernetes-on-nomad.git
$ cd kubernetes-on-arm/examples/coreos
$ ./setup.sh
```

Once the cluster is up and running you need to add Kubernetes networking:
```
$ vagrant ssh core-01
core@core-01 ~ $ sudo -u root -i
core-01 ~ # kon setup kubectl
core-01 ~ #
core-01 ~ # # Installs Weave Net
core-01 ~ # kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d n)"
core-01 ~ # # Adds DNS
core-01 ~ # kon addon dns
````

## Step 1 - Boot up all machines and login to the first

This step will create our four CoreOS servers that we will be using to install KON.

Boot up all machines using Vagrant:
```
$ git clone https://github.com/TheNatureOfSoftware/kubernetes-on-nomad.git
$ cd kubernetes-on-nomad/examples/coreos
$ vagrant up
$ vagrant ssh core-01
core@core-01 ~ $ sudo -u root -i
core-01 ~ #
```

## Step 2 - Install kon and generate a configuration

This step will show you how to install `kon`-tool and use it to generate a sample configuration.
```
core-01 ~ # mkdir -p /opt/bin \
&& curl -s -o /opt/bin/kon https://raw.githubusercontent.com/TheNatureOfSoftware/kubernetes-on-nomad/master/kon \
&& chmod a+x /opt/bin/kon
```

The first time you invoke `kon` it will pull down a docker image and install all `kon`-scripts to `/etc/kon`.

```
core-01 ~ # kon generate config
Unable to find image 'thenatureofsoftware/kon:0.2-alpha' locally
0.2-alpha: Pulling from thenatureofsoftware/kon
cc5efb633992: Pull complete 
4691a4109b46: Pull complete 
1ffbf2eb47bb: Pull complete 
14c0cddf0029: Pull complete 
c3c0d82b49b2: Pull complete 
f142b17bda3c: Pull complete 
Digest: sha256:5f7f0471081474e5e5ea4eb9190469ca34f538c5b435460ef906f404247262c7
Status: Downloaded newer image for thenatureofsoftware/kon:0.2-alpha
Installing kubernetes-on-nomad to directory: /etc/kon
Script installed successfully!

              .-'''-.                
             '   _    \              
     .     /   /` '.   \    _..._    
   .'|    .   |     \  '  .'     '.  
 .'  |    |   '      |  '.   .-.   . 
<    |    \    \     / / |  '   '  | 
 |   | ____`.   ` ..' /  |  |   |  | 
 |   | \ .'   '-...-'`   |  |   |  | 
 |   |/  .               |  |   |  | 
 |    /\  \              |  |   |  | 
 |   |  \  \             |  |   |  | 
 '    \  \  \            |  |   |  | 
'------'  '---'          '--'   '--' 
v0.2-alpha

Nomad not installed, Consul not installed, kubelet not installed, kubeadm not installed

[2017/10/10:12:04:04 Info] Generating sample configuration file /etc/kon/kon.conf
[2017/10/10:12:04:05 Info] You can now configure Kubernetes-On-Nomad by editing /etc/kon/kon.conf
```

You can view the sample config file `/etc/kon/kon.conf` to get a grasp of how to configure `kon`.
But for this example we have a config already prepared.

The next step is to copy the prepared config:
```
core-01 ~ # cp /example/kon.conf /etc/kon/
```

## Step 3 - Start bootstrap Consul

Next step is to install and start the bootstrap Consul instance.
Consul is run as a docker container.

First we need to install consul binaries. We do need the `consul`-binary for running commands
against the `consul agent` even if we run Consul as a docker container.
```
core@core-01 ~ $ kon consul install 
````

Then start the Consul bootstrap server:
```
core@core-01 ~ $ kon --interface eth1 consul start bootstrap
```

This will start the first instance of Consul and load `/etc/kon/kon.conf` in to the key-value store
to be shared by all other nodes. The command also enables all DNS queries to go through Consul.
You can test this by looking up the `consul`-service:
```
core-01 ~ # dig +short consul.service.dc1.consul
172.17.8.101
```

You can also verify that consul is running in docker:
```
core-01 ~ # docker ps -q -f 'name=kon-consul' --format "\n\n{{.Names}} Status:{{.Status}} Created:{{.CreatedAt}}\n\n"

kon-consul Status:Up 3 minutes Created:2017-10-10 12:13:24 +0000 UTC
```

## Step 4 - Start Nomad

Next step is to install and run Nomad:
```
core-01 ~ # kon nomad install
core-01 ~ # kon nomad start
```
We can verify that Nomad is running by verifying that the service is running:
```
core-01 ~ # systemctl status nomad
● nomad.service - Nomad
   Loaded: loaded (/etc/systemd/system/nomad.service; enabled; vendor preset: disabled)
   Active: active (running) since Tue 2017-10-10 12:19:01 UTC; 59s ago
     Docs: https://nomadproject.io/docs/
 Main PID: 1979 (nomad)
    Tasks: 10 (limit: 32768)
   Memory: 14.1M
      CPU: 354ms
   CGroup: /system.slice/nomad.service
           └─1979 /opt/bin/nomad agent -config /etc/nomad
 ```

You can also check that Nomad is running as a **server**:
```
core-01 ~ # nomad server-members
Name            Address       Port  Status  Leader  Protocol  Build        Datacenter  Region
core-01.global  172.17.8.101  4648  alive   true    2         0.7.0-beta1  dc1         global
```

A final step on our bootstrap server in to install Kubernetes binaries:
```
core-01 ~ # kon kubernetes install
```

## Step 5 - Start Nomad and Consul on all other nodes

Now it's time to switch to the rest of the nodes and join them all together to one Nomad cluster.
The difference here is how we start Consul by pointing at the bootstrap server:
```
core@core-02 ~ $ sudo kon --bootstrap 172.17.8.101 --interface eth1 consul start
```

Run the following commands on all other nodes:
```
core@core-02 ~ $ sudo mkdir -p /opt/bin \
&& sudo curl -s -o /opt/bin/kon https://raw.githubusercontent.com/TheNatureOfSoftware/kubernetes-on-nomad/master/kon \
&& sudo chmod a+x /opt/bin/kon \
&& sudo kon consul install \
&& sudo kon --bootstrap 172.17.8.101 --interface eth1 consul start \
&& sudo kon nomad install \
&& sudo kon nomad start \
&& sudo kon kubernetes install
```

You can verify that everything is working by checking the status of all Nomad nodes:
```
core@core-04 ~ $ nomad node-status -verbose
ID                                    DC   Name     Class         Version      Drain  Status
be7a4d44-0a09-877f-8b6e-ae5c1fc674be  dc1  core-04  kubelet       0.7.0-beta1  false  ready
197bc8ad-47a4-6c22-38a7-bddb5d1b96cd  dc1  core-03  kubelet       0.7.0-beta1  false  ready
f4ed5fda-1471-0bf4-5966-dd998bd0c56a  dc1  core-02  etcd,kubelet  0.7.0-beta1  false  ready
```


## Step 6 - Start etcd

Up until now we've only been starting our infrastructure for running Kubernetes. Now it's time
to start bringing Kubernetes up. You can pick any node in the cluster.

We first need to generate all Kubernetes konfiguration:
```
core@core-04 ~ $ sudo -u root -i
core-04 ~ # kon generate all
```

If you take a look at the configuration (you can use any node):
```
core-04 ~ # consul kv get kon/config | grep ETCD_INITIAL_CLUSTER
ETCD_INITIAL_CLUSTER=core-02=http://172.17.8.102:2380
ETCD_INITIAL_CLUSTER_TOKEN=etcd-initial-token-dc1
```
then you'll see that we have one etcd node. If you check the nomad config:
```
core@core-04 ~ $ cat /etc/nomad/client.hcl | grep node_class node_class = "etcd,kubelet"
```
Then you'll se that this node have the `node_class` set to `etcd`.
(You can configure as many `etcd` servers as you want.)

Now it's time to start `etcd`:
```
core-04 ~ # kon etcd start
core-04 ~ # # Check that the job is running
core-04 ~ # nomad job status etcd | grep "^Status"
Status        = running
```

## Step 7 - Start Kubernetes

Now finally let's start Kubernetes. This includes starting the control plane and all `kubelet`s and `kube-proxy`:
```
core-04 ~ # kon start control-plane \
&& kon start kubelet \
&& kon start kube-proxy
```

To check that all is working let's setup kubectl:
```
core-04 ~ # kon setup kubectl
core-04 ~ # kubectl cluster-info
Kubernetes master is running at https://kubernetes.service.dc1.consul:6443

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

You need to add Kubernetes Networking (Weave):
```
core-04 ~ # kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
serviceaccount "weave-net" created
clusterrole "weave-net" created
clusterrolebinding "weave-net" created
daemonset "weave-net" created
```

And finally add the Kubernetes DNS addon and check all your nodes:
```
core-04 ~ # kon addon dns
core-04 ~ # kubectl get nodes
NAME      STATUS    ROLES     AGE       VERSION
core-02   Ready     <none>    6m        v1.8.0
core-03   Ready     <none>    6m        v1.8.0
core-04   Ready     <none>    6m        v1.8.0
```


 



