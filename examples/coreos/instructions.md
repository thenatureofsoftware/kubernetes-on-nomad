# Setting up Kubernetes On Nomad using CoreOS (Vagrant)

This example will show you how to setup Kubernetes On Nomad on 6 CoreOS Vagrant servers.

TL;DR to bring the cluster up run:
```

```


## Step 1 - Boot up all machines and login to the first
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

This step will show you how to install kon and generate a sample configuration.
```
core@core-01 ~ $ sudo mkdir -p /opt/bin \
&& sudo curl -s -o /opt/bin/kon https://raw.githubusercontent.com/TheNatureOfSoftware/kubernetes-on-nomad/master/kon \
&& sudo chmod a+x /opt/bin/kon
```

The first time you invoke `kon` it will pull down a docker image and install all `kon`-scripts to `/etc/kon`.
```
core@core-01 ~ $ sudo kon generate config
Unable to find image 'thenatureofsoftware/kon:0.1-alpha' locally
0.1-alpha: Pulling from thenatureofsoftware/kon
cc5efb633992: Pull complete 
78edf86befdd: Pull complete 
dc6909d66ba6: Pull complete 
5daba30e82d4: Pull complete 
50d1bd5ec205: Pull complete 
d5190cd89ec5: Pull complete 
Digest: sha256:8b0bbddbc6eaf06bb57b369fe88da3fa5902bb3357ce2b31616d816ab841cff4
Status: Downloaded newer image for thenatureofsoftware/kon:0.1-alpha
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
v0.1-alpha

[2017/10/05:09:43:58 Info] You can now configure Kubernetes-On-Nomad by editing /etc/kon/kon.conf
```

You can view the sample config file `/etc/kon/kon.conf` to get a grasp how to configure `kon`.
But for this example we have a config already prepared.

The next step is to copy the prepared config:
```
core@core-01 ~ $ sudo mkdir /etc/kon \
&& sudo cp /example/kon.conf /etc/kon/
```

## Step 3 - Start bootstrap Consul

Next step is to install and start the bootstrap Consul instance.
Consul is run as a docker container.

First we need to install consul binaries. Even if we run Consul container so do we
need the `consul` binary for communicating with Consul.
```
core@core-01 ~ $ sudo kon consul install 
````

Then start the Consul bootstrap server:
```
core@core-01 ~ $ sudo kon --interface eth1 consul start bootstrap
[2017/10/05:12:20:09 Info] Switching nameserver to consul
[2017/10/05:12:20:09 Info] Creating symlink /etc/resolv.conf -> /etc/kon/resolv.conf
[2017/10/05:12:20:20 Info] Waiting for consul to start...
[2017/10/05:12:20:20 Info] Bootstrap Consul started!
[2017/10/05:12:20:20 Info] Success! Data written to: kon/config value: /etc/kon/kon.conf
```
This will start the first instance of Consul and load `/etc/kon/kon.conf` in to the key-value store
to be shared by all other nodes. The command also enables redirect all DNS queries to go through Consul.
You can test this by looking up the `consul`-service:
```
core-01 ~ # dig +short consul.service.dc1.consul
172.17.8.101
```

You can also verify that consul is running in docker:
```
core-01 ~ # docker ps -q -f 'name=kon-consul' --format "\n\n{{.Names}} Status:{{.Status}} Created:{{.CreatedAt}}\n\n"


kon-consul Status:Up 13 minutes Created:2017-10-05 12:20:09 +0000 UTC
```

## Step 4 - Start Nomad

Next step is to install and run Nomad:
```
core@core-01 ~ $ sudo kon install nomad

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
v0.1-alpha

/etc/kon/kon.sh: line 529: nomad: command not found
, Consul v0.9.3, Kubernetes , kubeadm 

[2017/10/05:12:35:05 Info] Loading configuration from /etc/kon/kon.conf       
[2017/10/05:12:35:10 Info] Nomad v0.6.3 installed
[2017/10/05:12:35:10 Info] OS: Container Linux by CoreOS
[2017/10/05:12:35:10 Info] Generating Nomad server config
```
We can verify that Nomad is running by verifying that the service is running:
```
core-01 ~ # systemctl status nomad
● nomad.service - Nomad
   Loaded: loaded (/etc/systemd/system/nomad.service; enabled; vendor preset: disabled)
   Active: active (running) since Thu 2017-10-05 12:35:10 UTC; 2min 21s ago
     Docs: https://nomadproject.io/docs/
 Main PID: 1815 (nomad)
 ...
 ```

You can also check that Nomad is running as a **server**:
```
core-01 ~ # nomad server-members
Name            Address       Port  Status  Leader  Protocol  Build  Datacenter  Region
core-01.global  172.17.8.101  4648  alive   true    2         0.6.3  dc1         global
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
&& sudo kon install nomad
```

## Step 6 - Start etcd

Up until now we've only been starting our infrastructure for running Kubernetes. Now it's time
to start bringing Kubernetes up.

We first need to generate all Kubernetes konfiguration:
```
```

If you take a look at the configuration (you can use any node):
```
core@core-04 ~ $ consul kv get kon/config
...
ETCD_INITIAL_CLUSTER=\
core-03=http://172.17.8.103:2380,\
core-04=http://172.17.8.104:2380,\
core-05=http://172.17.8.105:2380
...
```

Then you can se that we have for etcd nodes. If you check the nomad config:
```
core@core-04 ~ $ cat /etc/nomad/client.hcl | grep node_class
  node_class = "etcd,kubelet"
```
Then you'll se that these nodes have the `node_class` set to `etcd`.

Now it's time to start `etcd`:
```
```
 



