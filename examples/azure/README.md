# Setting up Kubernetes On Nomad using CoreOS on Azure

This example is not meant to show how to run Kubernetes on Azure, see [managed Kubernetes service (AKS)](https://azure.microsoft.com/sv-se/blog/introducing-azure-container-service-aks-managed-kubernetes-and-azure-container-registry-geo-replication/) for that.

First you need to install [Terraform](https://www.terraform.io/) and [Azure CLI](https://docs.microsoft.com/sv-se/cli/azure/install-azure-cli?view=azure-cli-latest).

## Steps

### Create resources
```
$ # Firts login
$ az login
$ terraform apply
```
```
$ # Find out the IP address of jump-box
$ az vm list-ip-addresses --output table
```

### Copy `kon.conf` and install `kon`
```
$ scp kon.conf core@<ip to jump-box>:~/
$ ssh core@<ip to jump-box>
core@jump-box ~ $ # Install kon
core@jump-box ~ $ sudo mkdir -p /opt/bin
core@jump-box ~ $ sudo curl -o /opt/bin/kon -sSL https://goo.gl/2RRdFu && sudo chmod a+x /opt/bin/kon
core@jump-box ~ $ sudo kon update
```

### Create the Nomad cluster
```
core@jump-box ~ $ kon -c kon.conf cluster apply
```

### Start Etcd and Kubernetes
```
core@jump-box ~ $ ssh core-01
core@core-01 ~ $ sudo -u root -i
core-01 ~ # eval $(kon --quiet nomad env)
core-01 ~ # kon etcd config
core-01 ~ # kon etcd start
core-01 ~ # kon kubernetes config
core-01 ~ # kon kubernetes start
core-01 ~ # kubectl get nodes
...
```