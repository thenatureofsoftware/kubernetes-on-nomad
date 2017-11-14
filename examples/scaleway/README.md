# Kubernetes On Nomad using Scaleway

This example show shows how to setup `KON` on [Scaleway](https://www.scaleway.com/).

## Requirements

* You need a [Scaleway account](https://www.scaleway.com/)
* [Scaleway CLI](https://github.com/scaleway/scaleway-cli)
* [Terraform](https://www.terraform.io/)

## Before we begin

Make sure `scw` is configured properly:
```
$ env | grep SCALEWAY
SCALEWAY_ORGANIZATION=...
SCALEWAY_REGION=par1
SCALEWAY_TOKEN=...
```
and that you have a `ssh-key` configured for accessing your Scaleway infrastructure (see https://www.scaleway.com/docs/configure-new-ssh-key/)

The simplest way to get started is to clone the `kubernetes-on-nomad` project:
```
$ clone https://github.com/TheNatureOfSoftware/kubernetes-on-nomad.git
$ cd kubernetes-on-nomad/examples/scaleway
```

Initialize Terraform and import the modules used and install the Scaleway provider:
```
$ terraform init && terraform get
```

Now let Terraform create your infrastructure (this will take about 10 minutes):
```
$ terraform apply
```
and you should get something like this:
```
Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Outputs:

jumpbox.id = fa396d33-xxxx-xxxx-xxxx-xxxxxxxxxxxx
jumpbox.ip = xxx.xxx.xxx.xxx
node01.id = 2e1edc77-xxxx-xxxx-xxxx-xxxxxxxxxxxx
node01.ip = 10.x.xx.x
node02.id = b206e149-xxxx-xxxx-xxxx-xxxxxxxxxxxx
node02.ip = 10.x.xx.x
node03.id = ad02fe70-xxxx-xxxx-xxxx-xxxxxxxxxxxx
node03.ip = 10.x.xx.x
node04.id = a2159d1e-xxxx-xxxx-xxxx-xxxxxxxxxxxx
node04.ip = 10.x.xx.x
node05.id = 40491c5c-xxxx-xxxx-xxxx-xxxxxxxxxxxx
node05.ip = 10.x.xx.x
node06.id = 3ee68884-xxxx-xxxx-xxxx-xxxxxxxxxxxx
node06.ip = 10.3.33.69
node07.id = d51e19d1-xxxx-xxxx-xxxx-xxxxxxxxxxxx
node07.ip = 10.x.xx.x
node08.id = cbfcb6f4-xxxx-xxxx-xxxx-xxxxxxxxxxxx
node08.ip = 10.x.xx.x
node09.id = 40033aeb-xxxx-xxxx-xxxx-xxxxxxxxxxxx
node09.ip = 10.x.xx.x
node10.id = 82f95918-xxxx-xxxx-xxxx-xxxxxxxxxxxx
node10.ip = 10.x.xx.x
```

The first machine is our `jumpbox` that has a public IP-address. This is the machine we will use to access
the rest of our infrastructure. The `jumpbox` is also the default gateway for all our machines with private IP-addresses. Without the gateway our nodes don't have access to the internet.

Our `kon`-cluster is described in `kon.conf` and we need to copy that configuration to our `jumpbox`:
```
$ scp kon.conf root@<jumpbox IP-address>:~/
```
and do `ssh` to that `jumpbox`:
```
$ ssh root@<jumpbox IP-address>
root@jumpbox:~# 
```

Now it's time to start up our Nomad cluster using the `kon`-tool (this will take about 10 minutes).
```
root@jumpbox:~# kon -c kon.conf cluster apply
```
The `cluster`-command reads the configuration file and generates certificates and installs Consul and
Nomad. The command also bootstraps our `nomad`-cluster and configures all DNS queries to go through
Consul. In the Terraform configuration we used for setting up our infrastructure (`main.tf`) all machines
got their own IP-address from a private IP address range. This gives us full control over our machines IP-address.

We can now inspect our cluster from any node:
```
root@jumpbox:~# ssh node10
```
First set the environment variables so that we can connect to Nomad
```
root@node10:~# eval $(kon --quiet nomad env)
```
List all server-members:
```
root@node10:~# nomad server-members
```
```
Name       Address        Port  Status  Leader  Protocol  Build      Datacenter  Region
node01.eu  192.168.1.101  4648  alive   false   2         0.7.0-rc3  par1        eu
node02.eu  192.168.1.102  4648  alive   true    2         0.7.0-rc3  par1        eu
node03.eu  192.168.1.103  4648  alive   false   2         0.7.0-rc3  par1        eu
```

List all nomad nodes:
```
root@node10:~# nomad node-status
```
```
ID        DC    Name    Class         Drain  Status
c127e200  par1  node10  kubelet       false  ready
7be30cfb  par1  node08  kubelet       false  ready
724f7090  par1  node09  kubelet       false  ready
588fbf77  par1  node04  etcd,kubelet  false  ready
7f76fce0  par1  node05  etcd,kubelet  false  ready
8ba2bafb  par1  node06  etcd,kubelet  false  ready
94146c77  par1  node07  kubelet       false  ready
```

Now it's time to start all Kubernetes components and we start with `etcd`:
```
root@node10:~# kon etcd config && kon etcd start
```
Verify that all `etcd` servers enters `running` state:
```
root@node10:~# watch nomad status etcd
```
```
Every 2.0s: nomad status etcd                                                                                                                                                                                                             Tue Nov 14 18:28:19 2017

ID            = etcd
Name          = etcd
Submit Date   = 11/14/17 18:25:37 UTC
Type          = system
Priority      = 100
Datacenters   = par1
Status        = running
Periodic      = false
Parameterized = false

Summary
Task Group  Queued  Starting  Running  Failed  Complete  Lost
etcd-grp    0       0         3        0       0         0

Allocations
ID        Node ID   Task Group  Version  Desired  Status   Created At
7b323a13  7f76fce0  etcd-grp    0        run      running  11/14/17 18:25:37 UTC
98b55d7f  588fbf77  etcd-grp    0        run      running  11/14/17 18:25:37 UTC
eb55a620  8ba2bafb  etcd-grp    0        run      running  11/14/17 18:25:37 UTC
```

Install `kubectl` and `kubeadm` using `kon`:
```
root@node10:~# kon kubernetes install
```

Configure Kubernetes:
```
root@node10:~# kon kubernetes config
```
and finally start Kubernetes:
```
root@node10:~# kon kubernetes start
```
When you start Kubernetes the whole control plane will be downloaded and started. This step can take some time.
You can check the progress from any node in your cluster:
```
root@jumpbox:~# ssh node03
root@node03:~# eval $(kon --quiet nomad env)
root@node03:~# nomad status kubelet
ID            = kubelet
Name          = kubelet
Submit Date   = 11/14/17 18:37:25 UTC
Type          = system
Priority      = 50
Datacenters   = par1
Status        = running
Periodic      = false
Parameterized = false

Summary
Task Group   Queued  Starting  Running  Failed  Complete  Lost
kubelet-grp  0       0         7        0       0         0

Allocations
ID        Node ID   Task Group   Version  Desired  Status   Created At
06926712  588fbf77  kubelet-grp  0        run      running  11/14/17 18:37:25 UTC
3b0fccd7  c127e200  kubelet-grp  0        run      running  11/14/17 18:37:25 UTC
3c90aff2  94146c77  kubelet-grp  0        run      running  11/14/17 18:37:25 UTC
6933e3b7  7be30cfb  kubelet-grp  0        run      running  11/14/17 18:37:25 UTC
bff84669  7f76fce0  kubelet-grp  0        run      running  11/14/17 18:37:25 UTC
dbe5e171  8ba2bafb  kubelet-grp  0        run      running  11/14/17 18:37:25 UTC
e1606539  724f7090  kubelet-grp  0        run      running  11/14/17 18:37:25 UTC
```
If you switch back to the node where you installed `kubectl` and started Kubernetes, you
can verify everything is working:
```
root@node10:~# kubectl get nodes
NAME      STATUS    ROLES     AGE       VERSION
node04    Ready     <none>    3m        v1.8.1
node05    Ready     <none>    3m        v1.8.1
node06    Ready     <none>    3m        v1.8.1
node07    Ready     <none>    3m        v1.8.1
node08    Ready     <none>    3m        v1.8.1
node09    Ready     <none>    3m        v1.8.1
node10    Ready     <none>    3m        v1.8.1
```

As a final step let's start `ghost` and verify that it's working:
```
root@node10:~# kubectl run ghost --image=ghost --port=2368
root@node10:~# kubectl expose deployment ghost --type="NodePort"
root@node10:~# kubectl describe service ghost | grep NodePort
root@node10:~# curl -sSLI http://192.168.1.106:31537
root@node10:~# curl -sSLI http://192.168.1.106:31537
HTTP/1.1 200 OK
X-Powered-By: Express
Cache-Control: public, max-age=0
Content-Type: text/html; charset=utf-8
Content-Length: 12291
ETag: W/"3003-nU52aBPdLPX3NcuKZm0l903kQUQ"
Vary: Accept-Encoding
Date: Tue, 14 Nov 2017 19:11:48 GMT
Connection: keep-alive
```

## When things go wrong

* You can always re-run `kon -c kon.conf cluster apply` and it will almost always fix any problems with a node.

* As long as Consul is up and running and working on the node, then you can run `kon setup node`.

* You can install `kubectl` on any node by running `kon kubernetes install`. Then get the config-file from Consul:
    ```
    root@node10:~# consul kv get kubernetes/admin/kubeconfig > ~/.kube/config
    ```

* All nodes uses a private (`192.168.100.0/24`) [`tinc`](https://www.tinc-vpn.org/) VPN network. The network
is currently not started on boot and needs to be started manually:
    ```
    root@node10:~# tincd -n scaleway
    ```

## Clean up

When you´re done with your infrastructure:
```
$ terraform destroy -force
```