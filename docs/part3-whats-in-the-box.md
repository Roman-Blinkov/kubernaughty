# Whats in the box?! (voiding the warranty)

Contents:
 - [Introduction](#intro)
 - [Kubernetes isn't a PaaS...](#paas)


<a name="intro"></a>
## Introduction (Part 3)

In parts 1 & 2 I walked though the problem summary and initial cluster
monitoring. I walked through the pre-made and other workbooks and graphs
available to you, disk layouts, etc.

**In this section, I'm taking off the 'I'm a user' gloves and pulling apart the
Kubernetes worker nodes. This includes **SSH'ing in and mutating things** - if
you are running a managed service, consuming one, or otherwise not in total
control of your cluster, I do not recommend doing this.**

That said - I feel the cloud has helped us collectively forget tools like sed,
awk, grep and host-level debugging and tuning. The lack of investment in
systems engineering / operations in companies consuming and operating Kubernetes
means that a lack of this knowledge and experience - especially Linux/Kernel/BPF
etc knowledge - at scale - can be a large blind spot for anyone thinking
Kubernetes is a PaaS (platform as a service).

![We remember](/images/who-remembers.jpg "Dats right")

On to the fun.

<a name="paas"></a>
## Wait, Kubernetes isn't a PaaS...

I lied. I'm not done with you yet. Let me drop some painful hard
truths (hot takes?) about Kubernetes and this entire stack:

It is not an application developer tool.

Period, full stop - Kubernetes is an abstraction of devices and
objects/resources within datacenter. This abstraction allows you to control,
manipulate and schedule work across any number of machines and resources within
that datacenter.

This means that Kubernetes itself is best thought of "Cluster as a Service" -
Kubernetes solves the problem of workload management across these abstracted
resources, but it is not something you would expose for HR to build websites on.

Kubernetes - and cluster orchestration systems in general are CaaS - cluster as
a service. This means they have more in relation to a normal virtual machine
rather than, an Azure App Service, Heroku, PKS, or Openshift.

The consequences of this 'difference in terms' is the difference between your
success with kube or your failure. If you go into your adoption thinking you
are going to hand kubectl, creds and the API server endpoint to your front line
application developers without **adding on all of the paas-like things you'll
need (CI/CD, app packaging, etc)** its going to be painful and slow.

There are no 'quick fixes' to changing the very nature of how you rationalize
and operate your applications at a global scale.

## Voiding the Warranty

In part 2 we left off with a lot of questions - given the issue summary, what
metrics could we begin to look at to know that this could be happening
(or other failure like this)?

Before we get started - let's double check the cluster to see what its been
up to (using my misleading chart):

![Idle Cluster util](/images/2-15-huh.png "Seems weird")

So. We have a cluster, and we have some nodes, and I'm a pre-cloud grumpy
engineer so the first thing I'm going to do is start SSH'ing into things - but
lets start first things first.

## Shaving yaks

Invariably we all have tools, setups and other things we all prefer. Since I'm
going to be sharing a lot of CLI things, I figured I'd show you my shell
setup/aliases:

```
# Kubernetes Helpers / shell

[[ -r "/usr/local/etc/profile.d/bash_completion.sh" ]] && \
  . "/usr/local/etc/profile.d/bash_completion.sh"
source /usr/local/opt/kube-ps1/share/kube-ps1.sh

export KUBECTX_IGNORE_FZF=1

# Centralize
source <(kubectl completion bash)
#source <(brew --prefix)/etc/bash-completion
source <(stern --completion=bash) #install stern


# Step 1: kubectl has 7 characters, make it 1
alias k=kubectl
# Step 2: follow your own preferred way
alias kg='kubectl get'
alias kl='kubectl logs '
alias kx='kubectl exec -i -t'
alias ctx='kubectx' #kubectx and kubens
alias cns='kubens'
alias kgno='kubectl get nodes -o wide'
```

Here are the tools each alias relies on:

- [Stern - multi pod log tailing](https://github.com/wercker/stern)
- [ctx - rapidly swap k8s cluster contexts](https://github.com/ahmetb/kubectx)
- [kubens - rapid namespace swapping](https://github.com/ahmetb/kubectx/#kubens1n)

- [The Azure CLI][azcli], kubectl, etc are already installed and pre-configured

## Command execution without SSH

If you have an AKS cluster - in my case the cluster is VMSS based, single
nodepool and you want to perform remote execution on the nodes without
going and exposing SSH and fiddling with keys (you should do that tho, its fun)
[Azure supports this][runcmd]:

```
az vmss run-command invoke -g "${resource_group}" -n "${vmss_name}" \
  --instance-id "${instance_id}" --command-id RunShellScript \
  -o json --scripts "${command}"
```

This doesn't scale much though - and you have to go spelunking around the
resource groups to find the nodes. So that's meh.

```
function vmms-cluster-rc {
  resource_group=$1
  cluster_name=$2
  shift 2
  command="$@"
  nrg=$(az aks show --resource-group ${resource_group} --name ${cluster_name} --query nodeResourceGroup -o tsv)
  scaleset=$(az vmss list --resource-group ${nrg} --query [0].name -o tsv)
  nodes=$(az vmss list-instances -n ${scaleset} --resource-group ${nrg} --query [].name -o tsv)
  node_ids=$(az vmss list-instances -n ${scaleset} --resource-group ${nrg} --query [].instanceId -o tsv)
  for i in $node_ids
    do
    echo "${nrg} -n ${scaleset} --instance ${i} --command-id RunShellScript -o json --scripts ${command}"
      az vmss run-command invoke -g "${nrg}" -n "${scaleset}" --instance "${i}" --command-id RunShellScript -o json --scripts "${command}" | jq -r '.value[].message'
    done
}
```

What the above does is all the grunt work for you - it cracks open the resource
group and scaleset, vmss instances etc and just iterates the list (sequentially)
firing off the command.

Look in the https://github.com/jnoller/kubernaughty/tools/ directory, there is
a hacky `vmssrc` script you can drop on your $PATH. I'm old and I like bash.

Here's an example using the vmssrc command:

[![asciicast](https://asciinema.org/a/95Su6QKv9uCJVfFv4wyxKHCCZ.svg)](https://asciinema.org/a/95Su6QKv9uCJVfFv4wyxKHCCZ)

We're still going to enable ssh - but keep that ^ in the back of your mind.

## Enabling SSH

AKS does not expose SSH to work nodes normally, it is not recommended, and
messing around as root on production systems is a terrible idea. Please read:

[Connect with SSH to Azure Kubernetes Service (AKS) cluster nodes](https://docs.microsoft.com/en-us/azure/aks/ssh)

And then read the [support details on worker nodes][support].

Finally, this piece by @jpetazzo "[If you run SSHD in your Docker containers,
you're doing it wrong!][sshwrong]"

Technically, I haven't broken anything on the cluster yet, so I don't really
need SSH - I just know I am going to need it, and want it and that I want to
give you a little tour of the node so YOLO.

Per the instructions above you have to update some vmss, root around for some
info. So I automated it.

In the https://github.com/jnoller/kubernaughty/tools/ directory, the script aksssh does what some of what you need:

[![asciicast](https://asciinema.org/a/nnWxY28G7Vqs5EaUJdj4vhtEp.svg)](https://asciinema.org/a/nnWxY28G7Vqs5EaUJdj4vhtEp)

**I recommend generating new/clean SSH keys for stuff like this - don't
re-use existing ssh keys**:

```
ssh-keygen -t rsa -b 4096 -C "sup@kubernaughty.ded"
```

As for running the ssh container along what the official docs tell you - you can
do that and `docker exec` into it. It's crummy and you lose thins that might be
handy filtering everything through the exec/SSH jump.

I spent a or two yakshaving distributed/balanced SSH bastions into the kube -
I'm a big fan of old school, ssh into the cluster nodes and debug. Normally, I
would just flip on a [Cluster SSH tool][csshtools] but after trying to get SSH
exposed to the WAN.. decided to skip and just use
[`kubectl-plugin-ssh-jumps`][kubectl-plugin-ssh-jump]

(You can also use https://github.com/kvaps/kubectl-node-shell)

Not today yakshaving satan!

![Don't worry](https://media0.giphy.com/media/bqalUGFYfyHzW/giphy.webp?cid=5a38a5a295fa9056ad795e4d096c7ebc10770010ad01b518&rid=giphy.webp "lol")

This kubectl ssh plugin is pretty handy - it does the needed ssh container/agent
forwarding/transparent jump that I want for now:

[![asciicast](https://asciinema.org/a/Q5eLhmj4HAI3HOHJt60FU7yrC.svg)](https://asciinema.org/a/Q5eLhmj4HAI3HOHJt60FU7yrC)

Cool, I has root now.

**UPDATE**: I spend some time yak shaving because I really hate typing things
so I made a wrapper: `tools/aksportal` - usage is pretty simple:

```
jnoller@doge kubernaughty (master) $ -> (⎈ |kubernaughty:default)$ tools/aksportal 0
Built AKS host map:
4 - aks-agentpool-57418505-vmss000004
3 - aks-agentpool-57418505-vmss000003
2 - aks-agentpool-57418505-vmss000002
1 - aks-agentpool-57418505-vmss000001
0 - aks-agentpool-57418505-vmss000000
```

All it does is wrap the awesome plugin above and dynamically build a host map.

[![asciicast](https://asciinema.org/a/295438.svg)](https://asciinema.org/a/295438)

## Just checking

Lets quickly recap the state of the cluster from the 'black box' point of view,
remember I haven't logged into kubernetes proper yet:

Nodes (and uname output):

```
aks-agentpool-57418505-vmss000000
    Linux aks-agentpool-57418505-vmss000000 4.15.0-1064-azure #69-Ubuntu SMP \
        Tue Nov 19 16:58:01 UTC 2019 x86_64 x86_64 x86_64 GNU/Linux
aks-agentpool-57418505-vmss000001
    Linux aks-agentpool-57418505-vmss000001 4.15.0-1064-azure #69-Ubuntu SMP \
        Tue Nov 19 16:58:01 UTC 2019 x86_64 x86_64 x86_64 GNU/Linux
aks-agentpool-57418505-vmss000002
    Linux aks-agentpool-57418505-vmss000002 4.15.0-1064-azure #69-Ubuntu SMP \
        Tue Nov 19 16:58:01 UTC 2019 x86_64 x86_64 x86_64 GNU/Linux
aks-agentpool-57418505-vmss000003
    Linux aks-agentpool-57418505-vmss000003 4.15.0-1064-azure #69-Ubuntu SMP \
        Tue Nov 19 16:58:01 UTC 2019 x86_64 x86_64 x86_64 GNU/Linux
aks-agentpool-57418505-vmss000004
    Linux aks-agentpool-57418505-vmss000004 4.15.0-1064-azure #69-Ubuntu SMP \
        Tue Nov 19 16:58:01 UTC 2019 x86_64 x86_64 x86_64 GNU/Linux
```

AKS worker nodes currently use Ubuntu 16.04 LTS, Microsoft and Canonical work
together to patch and maintain the images and kernels used. These kernels map
to the [`linux-azure` Ubuntu package on launchpad][kernel].

Security / Kernel updates are pulled by the worker nodes nightly (if an update
exists). The kernel updates are applied, but require a reboot to take effect.

AKS does not auto-reboot worker nodes for these patches - full node VM reboots
would cause customer workload to fail.

You should install and setup [`kured`][kured] for your clusters. When you do,
that actually, **before** you deploy anything to production:

> **Set Pod Disruption Budgets for your applications** - I'll go into why later
but effectively, no matter how much kube you rub on your app, if your don't set
disruption budgets (and resource limits) nothing will make your application
'just work' - Node reboots/crashes happen. Resource contention happens. It's
like the gravit(ies) of distributed systems.

Enough of that - let's also check the portal metrics too - the cluster has been
running for awhile now, so let's see what the idle cluster has been up to:

( **2020-01-22** picking up, cluster is now almost 2 weeks old)

![2 week IO](/images/2weeksIOPS.png "2 Week IO")
![2 week IOPS](/images/2weeksIOPS.png "2 Week IOPS")
![2 week misleading](/images/2weeksIOPS.png "Sup u cats")

From this view we can see things have sort of evened out - nothing seems to be
spiking anymore, except for the occasional blip.

# Cracking open the worker node

First things first - lets get the lay of the land. Rather than doing this node
by node, we're just going to look at Node 0.

> Note: Nodes 0, 1 and 2 are usually where things like CoreDNS pods land

Jumping onto node 0 and poking around:

```
azureuser@aks-agentpool-57418505-vmss000000:~$ ps ax
   PID TTY      STAT   TIME COMMAND
   890 ?        Ssl    0:00 /lib/systemd/systemd-timesyncd
  1269 ?        Ss     0:00 /sbin/dhclient -1 -v -pf /run/dhclient.eth0.pid -lf /var/lib/dhcp/dhclient.eth0.leases -I -df /var/lib/dhcp/dhclient6.eth0.leases eth0
  1423 ?        Ss     0:00 /usr/bin/python3 -u /usr/sbin/waagent -daemon
  1662 ?        Sl   259:36 python3 -u bin/WALinuxAgent-2.2.45-py2.7.egg -run-exthandlers
  3349 ?        Ssl  256:03 /usr/bin/dockerd -H fd:// --storage-driver=overlay2 --bip=172.17.0.1/16
  3375 ?        Ssl   32:32 containerd --config /var/run/docker/containerd/containerd.toml --log-level info
  4382 ?        Ssl  391:31 /usr/local/bin/kubelet --enable-server --node-labels=kubernetes.azure.com/role=agent,node-role.kubernetes.io/agent=,kubernetes.io/role=agent,agentpool=agentpool,storageprofile=man
  5354 ?        Sl     0:32 containerd-shim -namespace moby -workdir /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/moby/94da4a9b32752d748c4e05f683f813710e5e30b840633c0aef490bd847a038e9 -ad
  5355 ?        Sl     0:29 containerd-shim -namespace moby -workdir /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/moby/49a632ded2f32ecb3f08b14226199a3169aef9a376d1bd21cd3b0ead9f0f1fab -ad
  5360 ?        Sl     0:30 containerd-shim -namespace moby -workdir /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/moby/c0efa737df0f02443b0d17aa8331285e963155fa4299268eba2d063906bc56d1 -ad
  5626 ?        Sl     1:02 /opt/cni/bin/azure-vnet-telemetry -d /opt/cni/bin
  5886 ?        Sl     0:39 containerd-shim -namespace moby -workdir /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/moby/0718ae63aae1db8611832c01c1f98afeb41f3cdc5280370802e77b70a9a7bd47 -ad
  5905 ?        Ssl    2:10 /ip-masq-agent
  6098 ?        Sl     0:36 containerd-shim -namespace moby -workdir /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/moby/ce8171f92106560b30922605d13bfe1be37686b8fbd4a9c2ed3f6fc3944bfc71 -ad
  6115 ?        Ssl    8:24 /usr/bin/networkmonitor
  7503 ?        Sl     8:24 containerd-shim -namespace moby -workdir /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/moby/8d96bf208872ef179a7ce90a005dfce787d54c31a941ce358abdaff3355ed919 -ad
  7525 ?        Ss     0:00 /bin/bash /opt/main.sh
  8544 ?        Sl    67:53 /opt/microsoft/omsagent/ruby/bin/ruby /opt/microsoft/omsagent/bin/omsagent-81bcf7b3-2280-4374-8ba8-a5a953541c78 -d /var/opt/microsoft/omsagent/81bcf7b3-2280-4374-8ba8-a5a953541c78
  8617 ?        Sl     2:39 /opt/td-agent-bit/bin/td-agent-bit -c /etc/opt/microsoft/docker-cimprov/td-agent-bit.conf -e /opt/td-agent-bit/bin/out_oms.so
  8632 ?        Sl    10:16 /opt/telegraf --config /etc/opt/microsoft/docker-cimprov/telegraf.conf
 30062 ?        S      1:11 /opt/omi/bin/omiserver -d
 30063 ?        S      2:20 /opt/omi/bin/omiengine -d --logfilefd 3 --socketpair 9
 30591 ?        Sl     0:52 /opt/omi/bin/omiagent 9 10 --destdir / --providerdir /opt/omi/lib --loglevel WARNING
 30636 ?        Sl    29:33 /opt/omi/bin/omiagent 9 10 --destdir / --providerdir /opt/omi/lib --loglevel WARNING
 37524 ?        S<     0:00 /bin/sh /opt/microsoft/dependency-agent/bin/microsoft-dependency-agent-manager
 37572 ?        S<    13:04 /opt/microsoft/dependency-agent/bin/microsoft-dependency-agent
 44098 ?        Ss     4:59 bash /usr/local/bin/health-monitor.sh container-runtime
 92121 ?        Sl     0:03 containerd-shim -namespace moby -workdir /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/moby/49f3c995cf6a3649c88f14971e7fbc457c5511b80e28b7568fa969b553465bf8 -ad
 92709 ?        Sl     0:53 containerd-shim -namespace moby -workdir /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/moby/3a76f659549cf1ac7406f6024e739d044c96c1317884107c0f3c0413b173a699 -ad
 92727 ?        Ss     0:47 /bin/bash /lib/tunnel-front/run-tunnel-front.sh
 93131 ?        Sl     0:03 containerd-shim -namespace moby -workdir /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/moby/2c5a3beedb166c96d32a42890830165d73f143ca731e5d2fea8c62878626654c -ad
 93199 ?        Sl     0:03 containerd-shim -namespace moby -workdir /var/lib/docker/containerd/daemon/io.containerd.runtime.v1.linux/moby/84e55fbfd60cb1be7869c1a32e3be10691dfa45dbc9b22f467fb57592f3bac08 -ad
 93217 ?        Ssl    1:31 /hyperkube kube-proxy --kubeconfig=/var/lib/kubelet/kubeconfig --cluster-cidr=10.240.0.0/16 --feature-gates=ExperimentalCriticalPodAnnotation=true --v=3
128674 ?        Sl    13:59 /opt/microsoft/omsagent/ruby/bin/ruby /opt/microsoft/omsagent/bin/omsagent-81bcf7b3-2280-4374-8ba8-a5a953541c78 -d /var/opt/microsoft/omsagent/81bcf7b3-2280-4374-8ba8-a5a953541c78
128722 ?        Sl     0:16 python /var/lib/waagent/Microsoft.EnterpriseCloud.Monitoring.OmsAgentForLinux-1.12.17/omsagent.py -telemetry

```

I removed the normal system processes from the above - the only key things here
are that:

- We can see containerd, docker, and kublet processes running - the argument
  strings etc.
- Docker is realy Moby (`containerd-shim -namespace moby -workdir`)
- Docker's working directory is `/var/lib/docker/`
- There's at least one Python process (WALinuxAgent) running
- Ruby is in the processes tree too: (`)
- Azure Insights for containers agent's data dir is `/var/opt/microsoft/omsagent/`

`ps` is my first tool.

Since we're ultimately looking at disks:

```
azureuser@aks-agentpool-57418505-vmss000000:~$ cat /etc/fstab
# CLOUD_IMG: This file was created/modified by the Cloud Image build process
LABEL=cloudimg-rootfs	/	 ext4	defaults,discard	0 0
LABEL=UEFI	/boot/efi	vfat	defaults,discard	0 0
/dev/disk/cloud/azure_resource-part1	/mnt	auto	defaults,nofail,x-systemd.requires=cloud-init.service,comment=cloudconfig	0	2
```

```
azureuser@aks-agentpool-57418505-vmss000000:~$ df -h
Filesystem      Size  Used Avail Use% Mounted on
udev            6.9G     0  6.9G   0% /dev
tmpfs           1.4G  1.2M  1.4G   1% /run
/dev/sda1        97G   18G   79G  19% /
tmpfs           6.9G     0  6.9G   0% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
tmpfs           6.9G     0  6.9G   0% /sys/fs/cgroup
/dev/sda15      105M  3.6M  101M   4% /boot/efi
/dev/sdb1        28G   44M   26G   1% /mnt
tmpfs           1.4G     0  1.4G   0% /run/user/1000
```

* /dev/sdb - that's the virtual machine's ephemeral temp disk
* /dev/sda - that's your OS devices

Let's check resources - for these I'll use [`iotop` and `htop`][linuxiotools]
and since they look wicked cool, I recorded it:

[![asciicast](https://asciinema.org/a/QqP3azBOpgYgvkf8hPD8Vw4x1.svg)](https://asciinema.org/a/QqP3azBOpgYgvkf8hPD8Vw4x1)

`iotop` and `htop` are really fantastic - stop using plain top!

Notes:

* We can see based on htop that the kublet process is taking about 1gb of memory
  and theres a fair number of daemons that seem to be consuming around that
  amount
* The system *is* chatty - both htop and iotop show the regular spike in activity
  you usually see with always-on / polling daemons.
* iotop shows the regular I'm-polling-things activity - WALinuxAgent is pretty
  frequently popping up.

Nothing too strange. Though the memory usage seems... Eh? Let's check `free`:

```
root@aks-agentpool-57418505-vmss000000:~# free -ht
              total        used        free      shared  buff/cache   available
Mem:            13G        764M        8.0G        1.2M        4.9G         12G
Swap:            0B          0B          0B
Total:          13G        764M        8.0G
```

If you want all the details look in /proc:

```
root@aks-agentpool-57418505-vmss000000:~# cat /proc/meminfo
MemTotal:       14339492 kB
MemFree:         8402328 kB
MemAvailable:   13084164 kB
Buffers:          326048 kB
Cached:          4187112 kB
SwapCached:            0 kB
Active:          2147984 kB
Inactive:        2871060 kB
Active(anon):     455496 kB
...
```

So that means on (node 0 at least) from the OS perspective we have 13g, (12 gb)
available of ram (1gb of ram is saved by the linux kernel) with 8.1 gb free,
meaning that the currently installed daemons / processes for managing the
nodes is consuming ~4gb of worker node RAM in idle
state (Container insights, Azure CNI, http-application routing enabled).

## Memory, I knew him, Horatio

Just a real quick donut in the parking lot before moving on (ADHD rules) - there
is a lot of confusion around memory reservations / AKS worker nodes, so here it
is just re-arranged. Remember - in the above we have a 12 GiB RAM VM SKU, and
we know that ~8.1 GiB is free.

Now - we kinds know what the host has - but if you were to look at the available
memory from the perspective of the **kublet** (and therefore, the memory
available to your k8s workload) is different than the host ram.

[Per the AKS documentation:](https://docs.microsoft.com/azure/aks/concepts-clusters-workloads#resource-reservations)

>"memory.available<750Mi, which means a node must always have at least 750 Mi
  allocatable at all times. When a host is below that threshold of available
  memory, the kubelet will terminate one of the running pods to free memory on
  the host machine and protect it. This is a reactive action once available
  memory decreases beyond the 750Mi threshold."

Ok - so there is a minimum available of 750 MiB of ram before eviction kicks in.
There is also a **progressive** RAM reservation (`kube-reserved`)based on the
available ram:

> The above rules for memory and CPU allocation are used to keep agent nodes
  healthy, some hosting system pods critical to cluster health.
  These allocation rules also cause the node to report less allocatable memory
  and CPU than it would if it were not part of a Kubernetes cluster. The above
  resource reservations can't be changed.

tl;dr - if AKS does not reserve this ram as buffer, your workload and increased
load on the worker nodes, etc will cause the management daemons (scroll up to
the process tree) to fail. **This will lead to your cluster failing.**

Using the example from the docs for our VM sku:

```
>>> 1.6 / 7
0.2285714285714286
>>> 1.6 / 12
0.13333333333333333
>>> 1.6 / 13
0.12307692307692308
>>>
```
So, about a 12-13% buffer from the 13gb we've got - about 1.7gb so we're at:

* Available: 12gb
* base kube-reserved: 750mb
* Progressive reservation: 1.7gb
* Kernel reservation: 1gb

**Pre-reserved RAM: ~3.5 - 4 GB** - thats ~9GB of RAM available to your workload
which means **[you need to adjust your pod limits][k8sl]** lower than you
thought.

# Where the logs at?

Mostly, I wanted SSH access to be able to pour through the logs on each node.
Since I know how this all ends I figured I'd start there to set some context,
that being said - here's the actual reason I shaved all the yaks:

```
root@aks-agentpool-57418505-vmss000000:/var/log# ll
total 280952
drwxrwxr-x 16 root   syslog     4096 Jan 23 00:38 ./
drwxr-xr-x 13 root   root       4096 Nov 13 02:48 ../
-rw-r-----  1 root   root       4711 Dec 12 00:40 alternatives.log
drwxr-xr-x  2 root   root       4096 Nov 13 02:49 apt/
-rw-r-----  1 syslog adm           0 Jan 12 06:30 auth.log
d-w-rwxr-T 10 root   root       4096 Jan 16 21:32 azure/
-rw-r--r--  1 root   root    4959124 Jan 23 18:49 azure-cnimonitor.log
-rw-r--r--  1 root   root    5242940 Jan 23 00:38 azure-cnimonitor.log.1
-rw-r-----  1 root   root          0 Dec 12 00:40 azure-vnet-ipam.log
-rw-r-----  1 root   root      45757 Jan 22 22:37 azure-vnet.log
-rw-r--r--  1 root   root    2623001 Jan 23 18:49 azure-vnet-telemetry.log
-rw-r-----  1 root   root          0 Dec 12 00:40 blobfuse-driver.log
-rw-r-----  1 root   root          0 Dec 12 00:40 blobfuse-flexvol-installer.log
-rw-------  1 root   utmp          0 Nov 13 02:48 btmp
drwxrws--T  2 ceph   ceph       4096 Jun  1  2019 ceph/
-rw-r--r--  1 syslog adm      275946 Jan 10 23:23 cloud-init.log
-rw-r-----  1 root   root      12742 Jan 10 23:23 cloud-init-output.log
drwxr-xr-x  2 root   root       4096 Jan 22 22:37 containers/
-rw-r-----  1 root   root          0 Dec 12 00:40 daemon.log
drwxr-xr-x  2 root   root       4096 Oct  3 16:51 dist-upgrade/
-rw-r-----  1 root   root     220436 Jan 23 06:06 dpkg.log
drwxr-xr-x  2 root   root       4096 Nov 13 02:46 fsck/
drwxr-xr-x  2 root   root       4096 Dec 25  2015 glusterfs/
drwxr-xr-x  3 root   root       4096 Jan 10 23:23 journal/
-rw-r-----  1 syslog adm           0 Jan 12 06:30 kern.log
-rw-r-----  1 root   root          0 Dec 12 00:40 kv-driver.log
drwxr-xr-x  2 root   root       4096 Dec 12 00:40 landscape/
-rw-r-----  1 root   utmp   18701432 Jan 22 23:06 lastlog
-rw-r-----  1 syslog adm         386 Jan 10 23:40 localmessages
drwxr-xr-x  2 root   root       4096 Dec  7  2017 lxd/
-rw-r-----  1 syslog adm           0 Jan 12 06:30 messages
-rw-r--r--  1 root   root       8192 Jan 22 22:36 omsagent-fblogs.db
drwxr-xr-x  7 root   root       4096 Jan 22 22:38 pods/
drwxr-x---  2 root   adm        4096 Oct 21 15:31 samba/
-rw-r-----  1 syslog adm           0 Jan 12 06:30 syslog
drwxr-xr-x  2 root   root       4096 Dec 11  2017 sysstat/
drwxr-x---  2 root   adm        4096 Dec 12 00:40 unattended-upgrades/
-rw-r--r--  1 root   root     315847 Jan 23 11:40 waagent.log
-rw-r-----  1 syslog adm     4907038 Jan 23 18:50 warn
-rw-rw-r--  1 root   utmp      15360 Jan 22 23:06 wtmp
```

If you're not familiar with Linux logging/logfiles in here, take a moment to
read [this introduction](https://help.ubuntu.com/community/LinuxLogFiles).

But where are the other logs?! WHERE IS DOCKER?!

Oh, ffs systemd. I forgot, I'm old and systemd came in.

[Here's a cheat-sheet](https://www.linuxtrainingacademy.com/systemd-cheat-sheet/)

```
root@aks-agentpool-57418505-vmss000000:/var/log# systemctl show service docker
...
ExecStart={ path=/usr/bin/dockerd ; argv[]=/usr/bin/dockerd -H fd:// --storage-driver=overlay2 --bip=172.17.0.1/16 ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }
ExecStartPost={ path=/sbin/iptables ; argv[]=/sbin/iptables -P FORWARD ACCEPT ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }
ExecReload={ path=/bin/kill ; argv[]=/bin/kill -s HUP $MAINPID ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }
Slice=system.slice
```

Yay!

```
root@aks-agentpool-57418505-vmss000000:/var/log# sudo journalctl -fu docker.service
-- Logs begin at Tue 2020-01-14 07:31:18 UTC. --
Jan 22 22:26:05 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-22T22:26:05.232891814Z" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Jan 22 22:36:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-22T22:36:35.868649060Z" level=info msg="shim containerd-shim started" address="/containerd-shim/moby/67162d15433603b7ddd1174ac7b74929483ce9aa2854eb8bfb82f4f94fd48090/shim.sock" debug=false pid=116900
```

And Kubelet!

```
root@aks-agentpool-57418505-vmss000000:/var/log# sudo journalctl -fu kubelet.service
-- Logs begin at Tue 2020-01-14 07:31:18 UTC. --
Jan 23 20:43:39 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0123 20:43:39.164277    4382 container_manager_linux.go:457] [ContainerManager]: Discovered runtime cgroups name: /system.slice/docker.service
Jan 23 20:45:34 aks-agentpool-57418505-vmss000000 kubelet[4382]: W0123 20:45:34.722602    4382 reflector.go:302] object-"kube-system"/"container-azm-ms-agentconfig": watch of *v1.ConfigMap ended with: too old resource version: 2092641 (2093163)
Jan 23 20:47:06 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0123 20:47:06.699582    4382 logs.go:311] Finish parsing log file "/var/lib/docker/containers/84e55fbfd60cb1be7869c1a32e3be10691dfa45dbc9b22f467fb57592f3bac08/84e55fbfd60cb1be7869c1a32e3be10691dfa45dbc9b22f467fb57592f3bac08-json.log"
Jan 23 20:47:08 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0123 20:47:08.563586    4382 logs.go:311] Finish parsing log file "/var/lib/docker/containers/8d96bf208872ef179a7ce90a005dfce787d54c31a941ce358abdaff3355ed919/8d96bf208872ef179a7ce90a005dfce787d54c31a941ce358abdaff3355ed919-json.log"
```

So the docker / other interesting logs are in journalctl `service.name`. We can
follow along with those.

# If you've got the OOMKiller on you've got 99 problems you don't know.

Linux OOMKiller settings:

```
root@aks-agentpool-57418505-vmss000000:/var/log# sysctl -a | grep oom
vm.oom_dump_tasks = 1
vm.oom_kill_allocating_task = 0
vm.panic_on_oom = 0
root@aks-agentpool-57418505-vmss000000:/var/log# sysctl -a | grep kernel.panic
kernel.panic = 10
kernel.panic_on_io_nmi = 0
kernel.panic_on_oops = 1
kernel.panic_on_rcu_stall = 0
kernel.panic_on_unrecovered_nmi = 0
kernel.panic_on_warn = 0
```

> I may talk more about this later, (ed note- looking below, this was a lie)
  but suffice it to say my recommendation is that you _always_ panic on oom -
  the Linux OOMKiller in distributed systems - OOMs should always result in node
  death. I'm still mad no one believes me.

Fine, since I'm here, here's the host modification you should make:

```
sysctl vm.panic_on_oom=1
sysctl kernel.panic=5
```

You can also edit /etc/sysctl.conf, add those and reboot if you want

```
vm.panic_on_oom=1
kernel.panic=5
```

What this does is allow for a 5 second window where memory can be completely
saturated prior to forcing a kernel panic. The reboot setting means that the
node / VM should automatically reboot in the case of any type of kernel panic.

**Number 1**: You always want to reboot on a kernel panic in the cloud. You're
dealing with hundreds or thousands of nodes. Even one kernel panic and all you
have is a missing node you need to TTY into - good luck finding the panic logs,
and fml tty over javascript.

**Number 2**: Ignore kubernetes, ignore cgroups - ignore the entire container
stack. We're talking about a collected group of hundreds or more of individual
hosts. These hosts will sooner or later hit memory contention - it's not a
matter of if - its a matter of when. Dense container packing just makes it
worse.

The Linux OOMKiller was designed for _a_ host - it was meant to allow a host
to have a chance to free up resources by any means nessecary - it's arbitrary
and will kill things you rely on without realizing it.

> You can set OOMScoreAdjust to play with the oomkiller score in systemd service
  files btw. YOLOH!

When you're dealing with a huge geographic spread of linux hosts, you want them
to:

* All be in sync / in the same state (hence why we protect against net
  partitions)
* All be running the same processes in the same state
* All hosts must be in a **known** state!

Or you want them to _kill themselves_. Any node - any host in an unknown, or
worse unknowable state is the creeping death for distributed systems, this is
part of the reason we're taught to treat these things like cattle and not
pets: Kill them often.

The OOMKiller is a bit like a context-free nuke wielding drunk toddler busting
into your really intense operations center and going to town. It will kill
anything it has to in order to protect the kernel. When it does this, sometimes
lower lying processes like, a docker one may be killed. Or in memory SDN
daemons. In kubernetes, it will evict your entire workload, and possibly the
kubelet in failure modes. All of these things leave the node in an unknown,
unclean state - out of date iptables rules, missing containers, missing logs,
and so on. **Performing a hard reboot** instead returns the node to a known,
clean state in sync with the rest of the cluster.

When the OOMkiller evicts your workload containers / processes - what do you
think happens to your PVCs? Do your java daemons obey linux signals correctly?

Unknown state at scale is the death of services and systems, and having something
killing random processes and cgroups (even if you nice them nicely) is the
antithesis of being able to rationalize and observe a system. Just reboot.

LLook, since apparently this and
understanding system behavior makes me a crazy person, look at the [fallacies 
of distributed computing](https://en.wikipedia.org/wiki/Fallacies_of_distributed_computing).


for crying out loud. I'll invert it to be the **LAWS** of distributed computing:

* **The network is unrelaible**. In fact, software defined networking makes it even
  more fun because CPU and memory/IO starvation makes it unreliable. Not to
  mention everyone thinks they need hyper complex networking setups with bespoke
  jumps, hops and routes that make it even worse. Then you slap some mtls and
  a service mesh on that bad boy and make it even worse. So you buy bigger nics
  and VMs until eventually you're behind a 7-11 smoking dark fiber with AT&T.
* **Latency is never zero**: Just to prove this, later I'm going to give you a
  container that will absolutely demolish your system and workload latency. Why?
  You can not change physics. Trust me, I've tried.
* **Bandwidth is expensive and finite**: Have you looked at your bandwidth bills?
  I mean, really looked at them? Not only is the network unreliable, its bloody
  expensive, always limited, and also unreliable. Look at bandwidth/burst quotas
  for all cloud vendor network and VM devices, you don't have what you think you
  have.
* **The network is never secure**: Just go listen/watch awesome infosec people
  like [Ian Coldwater](https://twitter.com/IanColdwater). Follow whomever they recommend.
* **Topology doesn't change**: LOL 'infrastructure as code' - good one. Toplogy
  always changes, always partitions, and then Ted in IT is probably using those
  expensive giant routers you have to mine bitcoin probably.
* **There** are hundreds of administrators: Comeon yall. it's cloud, you know it
  and I know it. Kubernetes, given it mutates IaaS on behalf of a declared
  application need is one of those administrators, as well as all of those
  declared needs.
* **Transport cost is zero**: See bandwidth - but also, this means **failover** is
  expensive. Moving disks, creating new VMs, moving the workload from A to B -
  people think once again, you can break physics.
* **The network is chaos**: Not only is it not homogenous - it might as well be
  your single most important failure point in the entire system. Go ahead, ask
  what we did before we could all poorly re-implment RAFT to protect against
  bizarre networking issues.

Must-read for the OOMKiller:

* https://lwn.net/Articles/317814/
* https://lwn.net/Articles/761118/

Uhhhh anyway. I've got root. Onto part 4.

[Continue on to Part 4: Lets kill a Kubernetes]()


[csshtools]: https://medium.com/@joantolos/cluster-ssh-tool-using-macos-a66930eeada6
[azcli]: https://docs.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest
[runcmd]: https://docs.microsoft.com/cli/azure/vmss/run-command?view=azure-cli-latest
[sshwrong]: https://jpetazzo.github.io/2014/06/23/docker-ssh-considered-evil/
[support]: https://docs.microsoft.com/en-us/azure/aks/support-policies#aks-support-coverage-for-worker-nodes
[kernel]: https://launchpad.net/ubuntu/+source/linux-azure
[kured]: https://docs.microsoft.com/en-us/azure/aks/node-updates-kured
[kubectl-plugin-ssh-jump]: https://github.com/yokawasa/kubectl-plugin-ssh-jump
[linuxiotools]: https://www.opsdash.com/blog/disk-monitoring-linux.html
[k8sl]: https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/
<!--stackedit_data:
eyJoaXN0b3J5IjpbMTcxODA5MDAxNCwyMTUyMDY3NzVdfQ==
-->