# Local Kubernetes Testing Environment

There are lots of tools that will provide and setup a local Kubernetes cluster. This tutorial focuses on setting up a single VM local cluster running [K3s](https://k3s.io), a Rancher lightweight Kubernetes distribution. While this approach does require additional overhead vs some other local Kubernetes tooling, it provides the benefit of a more consistent production like look and feel.



## Lima

[Lima-VM](https://lima-vm.io) provides a cross platform method or orchestrating Virtual Machines instances on a local MacOS (ARM/x86) machine, that will be used to host the Kubernetes cluster.

> Lima provides the feature to allow [Intel (x86) containers running within an ARM VM on an ARM Host](https://github.com/lima-vm/lima/blob/master/docs/multi-arch.md#fast-mode-2). This provides native speed at the VM level, and only requires emulation at the container level within the VM.

### Installation

Installation via Homebrew

```bash
brew install lima
```

#### Networking

By default Lima only enables user-mode networking aka "slirp", which provides an interface/address which is not accessible from the host by design. VMnet needs to be configured to allow accessing the guest IP from the host, this is accomplished using using [socket_vmnet](https://github.com/lima-vm/socket_vmnet).

The following recipe is used to install and configure Lima to utilize socket_vmnet

```bash
# Install socket_vmnet
brew install socket_vmnet

# Configure Lima Networks
socket_vmnet_path=$(readlink -f $(brew --prefix)/opt/socket_vmnet/bin/socket_vmnet | \
sed 's_/_\\/_g') && sed -i -re "s/^(  socketVMNet:).*/\1 \"$socket_vmnet_path\"/"  ${HOME}/.lima/_config/networks.yaml

# Set up the sudoers file for launching socket_vmnet from Lima
limactl sudoers | sudo tee /etc/sudoers.d/lima
```



## Multipass

[Multipass](https://multipass.run) provides a cross platform method for orchestrating the Virtual Machine instances on your local Linux machine, that will be used to host the Kubernetes cluster.

> Apple hardware has moved from x86 to ARM CPU architecture, Multipass will only run VMs using the same CPU architecture as the host. This limitation prevents newer Apple hardware from running x86 Virtual Machines to mimic QA,Stage and Production environments. 
>
> ** Its recommended that MacOS users, reference the Lima sections **

### Installation

Multipass provides multiple methods for installation on your local platform, you can view their [documentation here](https://multipass.run/install) or see recommended installation methods below

### Trouble Shooting

#### Cloud-init

Within the VM instance that was created you can examine the vendor-data that was merged from Multipass and Cloud-init by looking at files in `/var/lib/cloud/instances/`

[Reference](https://canonical.com/blog/using-cloud-init-with-multipass)



## Create Local Virtual Machines Instances

Each virtual machine orchestrator (lima,multipass) has dedicated `launch_localk3s.sh` utilities for both single and multi-node instances. Clusters are configured without the default ingress ([Traefik](https://traefik.io/) ) and load balancer [ServiceLB](https://github.com/k3s-io/klipper-lb) (formerly Klipper LoadBalancer), to allow using ingress-nginx and MetalLB.

### Single Node Instance

To create a local K3s single node (standalone) Kubernetes instance, execute the following:

> The following arguments and defaults values are lised below:
>
> * -c [ default = 1 ] : VM CPU Count
> * -d [ default = 20 ] : VM Disk size in GiB
> * -m [ default = 4 ] : VM Disk size in GiB
> * -v [ default = v1.27.3+k3s1 ] : K3s install version

#### Using Lima

```bash
./lima/single-node/launch_localk3s.sh {optional arguments}
```

#### Using Multipass

```bash
./multipass/single-node/launch_localk3s.sh {optional arguments}
```

### Multi-Node Instance

Two flavors of multi-node cluster instances are available for creation. The default being a multi-node cluster with a single server ( control-plane/etcd ) and X numberOf agent nodes. The latter being a multi-node cluster with numberOf server ( control-plane/etcd ) nodes.

> The following arguments and defaults values are lised below:
>
> * -c [ default = 1 ] : VM CPU Count
> * -d [ default = 20 ] : VM Disk size in GiB
> * -m [ default = 4 ] : VM Disk size in GiB
> * -s [ default = 3 ] : K3s Cluster size (total node count)
> * -t [ default = agent ] : K3s cluster type multi-(agent[default]/server)
> * -v [ default = v1.27.3+k3s1 ] : K3s install version

#### Using Lima

* Single server ( control-plane/etcd ) and N (specified) number agents
  ```bash
  ./lima/multi-node/launch_localk3s.sh {optional arguments}
  ```

#### Using Multipass

* Single server ( control-plane/etcd ) and N (specified) number agents
  ```bash
  ./multipass/multi-node/launch_localk3s.sh {optional arguments}
  ```

  

## Additional Tools / Tricks

Each virtual machine orchestrator (lima,multipass) also have dedicated utilities to assist in various additional functions, such as destruction and cleanup of a cluster. Each of these utilities are located with in a subdirectory for each orchestrator (lima,multipass).

### delete_localk3scluster.sh

The `delete_localk3scluster.sh` utility is used to destroy the current local K3s cluster by stopping and purging the VMs along with performing clean for any entires added to the local hosts (laptop/desktop) `/etc/hosts` file

```bash
./lima/delete_localk3scluster.sh
or
./multipass/delete_localk3scluster.sh
```

### update_etc_hosts.sh

The `update_etc_host.sh` utility is used to help provide easy access to workloads running within the local K3s Kubernetes cluster by modifying your local hosts (laptop/desktop) `/etc/hosts` file with address provided by MetalLB from its configured pool for services or ingresses.

This is accomplished by issuing `kubectl` command against the local Kubernetes cluster to provide a list of ingresses / service and their corosponding external-ip addresses. 

* For each ingress the HOST(url) is used for the entry in `/etc/hosts`. 
* For each service the NAME is used along with the prefix `local-` and the suffix `-svc`

```bash
./lima/update_etc_hosts.sh
or
./multipass/update_etc_hosts.sh
```

### update_kube_configs.sh 

The `update_kube_configs.sh` utility obtains the kubeconfig file from the local K3s CI instance and update the **.clusters.[].cluster.server** key value with the clusters external-ip addresses required for remote access.

Using localk3s alternative kubeconfig file:

```bash
kubectl --kubeconfig=${HOME}/.kube/localk3s get nodes
```

Anytime a cluster is restarted this command can be re-run to set the correct values for remote access

```bash
./lima/update_kube_configs.sh
or
./multipass/update_kube_configs.sh
```
