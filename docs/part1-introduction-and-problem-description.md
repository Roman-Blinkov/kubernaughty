# Diagnosing and chasing Kubernetes Kubernaughties

Contents:

* [Introduction](#intro)
* [Technical Introduction](#techintro)
* [Root Cause / Known Failures](#iknowthereisnorootcause)
* [Quotas leading to failure](#quotafail)


<a name="intro"></a>
## Introduction

> "What you measure is what you get" - Aristotle

Hi, my name is [Jesse][twitter]. I'm an engineer/developer by background -
currently I'm a program manager on [AKS][aks] (Azure Kubernetes Service). This
means a few things:

- The opinions, statements, etc located in this repository and on my social
  media accounts, etc are mine.
- The above means there may be typos or editing nightmares
- Kubernetes 'as a user' isn't my strong suit - my background is in distributed
  systems (predating kube, they do exist), distributed fault tolerant storage
  systems / systems engineering (linux). So apologies if I don't know all the
  cool commands.
- I've also been far away from a front line engineering role for some time, that
  means I probably don't know your cool tool or whatever.

Technical and other disclaimers:

- The commands and tools in this repository may or may not result in the
  wholesale destruction of your Kubernetes cluster should you run things
  without checking.
- If you are using a managed service (AKS, GCP, EKS) the stuff I go into here
  may or may not apply. Additionally, execution of some of these things may
  void your warranty / SLA / etc.

Full technical mandatory legal CYA:

![i have no idea what I'm doing](https://media2.giphy.com/media/xDQ3Oql1BN54c/giphy.gif?cid=5a38a5a24f04dc07319f32087d79a3dbc3b9849ccf0f0fcc&rid=giphy.gif "no, seriously")

Finally:

I've worked for various cloud providers and enterprise / large scale vendors/etc
through the years. In all of those years I have tried to stay objective, fair,
honest, and candid. This means that while I work for Microsoft/Azure/AKS and
I will not disclose internal information, I do not redact or otherwise doctor
or change things due to my employer.

My goal with this is to walk through (end to end) testing and debugging
Kubernetes installations from an operator perspective regardless of vendor -
being able to self root-cause and understand an issue is critical even for
users using managed or hosted solutions.

As I investigate / re-create other failure modes, I will continue to expand
`kubernaughties`.

<a name="techintro"></a>
## Technical introduction

_This project/documentation expands on this [GitHub][iopstsg] issue I published.
Text from that article is reproduced here and modified and / or expanded as
needed._

Over the past few months, I've been helping to investigate a series / family of
failures leading to to users reporting service, workload and networking
instability when running under load or with large numbers of ephemeral,
periodic events (jobs). These failures (covered below) are the result of
Disk IO saturation and throttling at the file operation (IOPS) level.

Cluster worker node VMs are regularly disk IO throttled and/or saturated on
all VM operating system disks due to the underlying quota of the storage device
potentially leading to cluster and workload failure.

This is a common 'IaaS mismatch' scenario and pitfall many users encounter when
moving to cloud in general with or without Kubernetes in play. With the
container stack (docker, kubernetes, CNI, etc) all in play, this pitfall
becomes an increasingly difficult to debug series of cluster and workload
failures.

If you are seeing worker node/workload or API server unavailability,
NodeNotReady, Docker PLEG and loss of cluster availability I recommend that
you investigate this family of issues on your own infrastructure and host.

<a name="description"></a>
## Issue Description

Most IaaS cloud providers, Azure included, use network-attached storage
supplied by the storage service (Azure Blob, etc) for the Operating system /
local storage for a given Virtual Machine by default for many VM classes.

Physical storage devices have limitations in terms of bandwidth and total
number of file operations (IOPS) but this is usually constrained by the
physical device itself. Cloud provisioned block and file storage devices also
have limitations due to architecture, service **and**  device-specific limits
(quotas).

For example, your Azure subscription may only allow you to have a single Azure
Blob storage device, your limit is 1 across that subscription - but that blob
storage device, network card, or VM **also** has quotas/limits specific to
maintain the QoS for that device.

These service limits/quotas enforced by the services (storage in this case)
are layered - Service Quotas -> Regional Quotas -> Subscription Quotas ->
Device Quotas. When the lesser of any value in this stack is exceeded, all
layers above that will become throttled.

Examining the user reported failures and commonality, we identified that user
workloads were exceeding quotas set by Azure Storage to the operating system
(OS) disk of cluster worker nodes (Max IOPS).

This issue impacts your cluster's worker nodes. Depending on your
setup or provider, worker nodes may be fully, partially, or not at all managed
this means that in many scenarios, worker node issues like this may be left
to the user or look like service level failures.

Due to the nature of the failure and the symptoms user would not be aware
to monitor for these metrics on worker nodes.

Additionally, many users design their own metrics and monitoring suites, and
rely heavily on the in-memory metrics returned by Kubernetes. These metrics are
incomplete, and DIY-ed monitoring suites frequently miss key system level
metrics needed to root-cause issues. Monitoring Kubernetes and workloads
**well** on Kubernetes requires investment on your implementation teams.

I encourage you to test your configurations and setup for these failures - bug
reports online suggest that this is a common and widespread issue that is not
well understood. I'm not casting shade at anyone here, so don't push me frank.

> Side note: "why don't I see this on infrastructure or VMs I build?" Thats a good
> question, why aren't you seeing it - you should! Physical servers and devices
> all have specific behaviors when they hit IO limits, network or other
>limitations. If you are not testing your entire workload under non-synthetic
>/ peak traffic + 25% levels you won't know what the *actual* failure would be
>using physical devices.
>
>PS: You're probably not doing fleet level/global and regional testing, trend and
>error analysis and testing all the way down to the node level.
>
>PPS: Are you accounting for software/service/system overhead when doing your
>capacity planning - **after** you test peak load?

<a name="iknowthereisnorootcausesigh"></a>
## Root Cause / Known failures

During the investigation, we identified this issue as contributing
significantly or being the sole cause for the following common error / failure
reports:

* Cluster nodes going NotReady (intermittent/under load, periodic tasks)
* Performance and stability issues when using istio or complex operator
  configurations.
* Networking Errors (intermittent/under load) and Latency (intermittent) (Pod,
  container, networking, latency inbound or outbound) including high latency
  when reaching other azure services from worker nodes.
* API server timeouts, disconnects, tunnelfront and kube-proxy failures under
  load.
* Connection timed out accessing the Kubernetes API server
* Slow pod, docker container, job execution
* Slow DNS queries / core-dns latency spikes
* "GenericPLEG" / Docker PLEG errors on worker nodes
* RPC Context deadline exceeded in kubelet/docker logs
* Slow PVC attach/detach time at container start or under load / fail over

The root-cause of this issue is resource starvation / saturation on the worker
nodes due to throttling of the Operating System (OS) disks. High amounts of
docker/container load, logging, system daemons, etc can exceed the allowed IOPS
quota for the OS Disk in most configurations.

These failures will also occur in most IO saturation cases (exceeding IOPS,
cache, etc) or where users have configured remote storage devices as root
devices not isolating the kernel data path (Database people, u get me fam?).

Exceeding the IOPS or bandwidth quotas, saturating the network (network attached
devices) will result in the OS disk of the worker nodes going into IOWait - from
the perspective of all processes, the disk is slow, completely unresponsive, and
existing IO requests may block until kernel / node failure or timeout.

As everything on Linux is a **file** (including network sockets) - CNI, Docker
and other critical services that perform any (network or disk) I/O will fail as
they are unable to read off of the disk.

> Hey! Socket IO shouldn't impact the main data path! This is true - it should
not, but it is *impacted* by IO starvation. Socket files / daemons that use
sockets perform read(), sync() and other filesystem **operations** again that
file. If the disk is stuck, read(), sync() and therefore the networking daemons
themselves - and single threaded storage drivers (common NFS, Samba/CIFS and
other drivers don't always offload the hot-path and being resident in the kernel
means they'll take the box down with a kernel panic).

When the OS disk gets trapped in IOWait / timeouts such as this - the Linux
kernel will panic and fail in some cases - this is due to the kernel or loaded
in-memory drivers (such as remote filesystem drivers) panic-ing and crashing
the host. This will look like a random node failure requiring a hard reboot.

### Trigger

The **trigger** that causes the disk device to timeout/go into IOWait in this
specific scenario is the worker node exceeding the allowed IOPS
(file operation) quota put in place by cloud IaaS. When the quota is exceeded,
the OS disk for those nodes will become unavailable leading to this failure.

The following can cause high IOPS triggering the throttling on any given Linux
host include high volumes of Docker containers running on the nodes (Docker IO
is shared on the OS disk), custom or 3rd party tools (security, monitoring,
logging) running on the OS disk, node fail over events and periodic jobs. As
load increases or the pods are scaled, this throttling occurs more frequently
until all nodes go NotReady while the IO completes/backs off.

HPAs or other auto-scale-up or scale-down tools may also trigger this.

 <a name="quotafail"></a>
# Quotas leading to failure

When a VM, or in this case - an AKS cluster - is provisioned the OS disks for
the worker nodes is **100 GiB**. A common assumption would be that the IOPS
quota for the VM would dictate the speed or capability of the OS disk.

This is not the case - we'll use that 100 GiB (128 GiB actual) and the DS3_v2
VM SKU for this example. The DS3_v2 has the following limits:

![NodeQShort](https://user-images.githubusercontent.com/51528/71927583-025e4300-3153-11ea-8fc2-8e719763e6ef.png)

The Max IOPS and Max Throughput value shown here is the **total** allowed for
the VM SKU shared across **all** storage devices. This sku has a maximum of
12800 IOPS - this means that to maximize the VM's IOPS, I would need to have 4
storage devices (drives attached to the VM) with a maximum IOPS of 3200 (12800
/ 4) or a single device with a maximum IOPS value of 12800 (P60 managed disk
with a size of 8 TiB).

Maximum IOPS and bandwidth *are guaranteed* on most IaaS up to the limit - but
not **exceeding** it unless temporary burst scenarios are supported. Due to the
nature if this issue, burst limits will also be exceeded.

The disk devices / drives map to specific disk classes or tiers in Azure and
other IaaS providers. On Azure, the default is Premium SSD storage so we can
look at the size (128 GiB) and map that to the
**P10** disk tier with a Max IOPS of **500** and a Max Throuput of 100 MiB/sec.

![Disk Sizes Trimmed](/images/disk-sizes-trimmed.png "p10 disk tier")

**This means, using our example DS3_v2 SKU (VM Max IOPS 12800) has an OS disk
Max IOPS of 500 (P10 Class Max IOPS 500) not 12800**. You can not exceed these
values without VM / Storage level hosts pushing back at the VM layer.

Here is the issue visualized:

![Disk Quota Conflict](/images/quota-simple.png "thats ur problm right thar")

When quotas are stacked with VM, networking and storage, the **lesser** of the
quotas applies first, meaning if your VM has a maximum IOPS of 12800, and the
OS disk has 500, the maximum VM OS disk IOPS is 500, exceeding this will result
in throttling of the VM and it's storage until (if) the IO load backs off.

These periods of throttling of the VM due to the mismatched IaaS resources
(VM/Disk vs workload) directly impacts the runtime stability and performance
of your Kubernetes clusters.

For more reading on Azure / VM and storage quotas, see "[Azure VM storage performance and throttling demystified](https://blogs.technet.microsoft.com/xiangwu/2017/05/14/azure-vm-storage-performance-and-throttling-demystify/)".

**Note**: These limits and quotas can not be expanded or extended for any
specific storage device, VM or subscription as they protect QoS for all
customers.

# Can I just increase my disk size to work around it before you keep talking

Short answer? No.

Lets go back to this chart for a second:

![Disk Sizes Trimmed](/images/disk-sizes-trimmed.png "p10 disk tier")

Right off the bat - you can see that **every** disk tier has an IOPS cap. Simply
boosting this to a large disk means that you're only delaying the inevitable
(because the problem is not fixed, and IOPS will eventually be exhausted).

Linux also has a 2 TiB disk partition limit. You can add and have larger
partitions, but most system daemons and applications will not be able to
actually use the additional space. That means you have a hard IOPS cap
(per the chart) of 7500 IOPS (due to the 2 TiB partition limit).

7500 sounds like a lot, but its not unless **you know exactly** how much the OS
and the entire stack above will consume under a failover event under **peak**
load (applying peak application load and then forcing 1-2 node failures should
help identify the high water mark - but also test a cold-boot-to-hot-load,
containers cost a lot to spin up initially, causing thundering herd IO).

You can increase the size of the OS using ARM on Azure, however scale/mutate in
place is not supported for AKS worker nodes. Additionally, see above - clusters
under load utilizing a 2 TiB OS disk will still be throttled.

Additionally: You'd be paying full price for a 2 TiB OS disk - when all you need
is the IOPS performance, not the space.

Most users when they encounter these failures simply over provision. This
includes pre-allocating that 2 TiB disk, increasing the VM SKU size, etc - this
changes the *time until* they hit the issue especially with StatefulSet,
periodic/batch workloads running densely (packing all nodes densely with
application containers, not setting resource limits) - and during that time
you're paying for completely unutilized disk and VM resources.

Your likelihood of hitting this is directly related to the load / traffic your
application (therefore the cluster) is under. The higher the load, the higher
the likelihood.

I will go into more details and pros/cons on mitigation & cluster design
considerations later.

[Continue on to Part 2: Cluster setup and basic monitoring](/docs/part2-basic-setup.md)

[aks]: https://docs.microsoft.com/en-us/azure/aks/
[twitter]: https://twitter.com/jessenoller
[iopstsg]: https://github.com/Azure/AKS/issues/1373
