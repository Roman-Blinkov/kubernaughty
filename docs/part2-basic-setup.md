
# Cluster Setup & Basic Monitoring

[See part 1 for issue summary.](https://raw.githubusercontent.com/jnoller/kubernaughty/master/docs/part1-introduction-and-problem-description.md)

Contents:

* [Introduction](#intro)
* [Azure Insights setup](#insights)
* [Idle IO? The plot thickens](#idleio)

<a name="intro"></a>
## Quick Intro

This picks up from Part 1, this is part narration/notes and part journal vs
part one. This follows the actual steps / back tracking needed to identify
these failures.

## Basic cluster setup and configuration

* Provider: AKS
* Region: EastUS2
* Resource Group: kubernaughty
* Kubernetes version: 1.15.7
* 5 Nodes DS3_v2
  * 4 vCPU, 14 GiB RAM, 16 Data Disks, Max IOPS 12800, 28 GiB temp storage
* HTTP Application routing enabled
* Azure container monitoring enabled
* Azure CNI cluster
* Agentpool: aks-agentpool-57418505-vmss

## Azure Container Insights / Monitoring setup

As I am approaching this as a user, I've enabled Azure Container insights, if
you select the different workbooks & report tabs when viewing the cluster you
will see pre-created charts that show some of the key base metrics you should
be watching at all times for Kubernetes clusters:

![azure insights](/images/azureinsights1.png "Azure Insights")
![azure insights DiskIO](/images/insights-diskio.png "Azure Insights DiskIO")
![azure insights DiskIO2](/images/insights-diskio-2.png "Azure Insights DiskIO2")

Critical metrics here are:

* Kublet/
  * Overview By Operation Type
  * Overview By Node (% errors, operations, success rate)
* Node Disk IO/
  * % Disk Busy / Trend
  * % IOPS / Trend

If we look closer at the Node Disk IO we can already see some IO spikiness I
would keep my eye on:

![Why are the disks... so busy?](/images/whyisthediskbusy.png "Why is disk busy already so high?")

Hmmmmmmm.... which disks are busy?

![DEV SDA IS MADE OF PEOPLE](/images/osdiskuhoh.png "sda is the OS disk, the OS disk... is busy...")

**note**: Looks like the disks spike in usage during cluster creation,
          provisioning etc as one would expect. Disk busy across the cluster is
          averaging 0.17% - looking at the nodes each operating system disk is
          averaging 3.8%/4% up to 4.9% with node 0003 being highest with 4.94%
          average.

## Azure Insights: Making a custom chart

Since I already know how this play ends (it's a tragedy Brent) - I'll show you
the chart you can build using Azure Insights (Metrics View) that tracks some
of the metrics I will be going into more later:

![bling bling](/images/iops-busy-error-cpu-memory-brent.png "Watch me whip, watch me nae nae")

Key metrics I've plotted:

* Disk busy percentage
* IOPS in progress (hint!)
* Kubelet Operation error count (o_O)
* cpuUsagePercentage
* memoryRssPercentage (if Rss is an acronym (RSS), why isn't it capitalized?)
* memoryWorkingSetPercentage

<a name="idleio"></a>
## Idle IO? The plot thickens

The cluster above was created / deployed on 2019-01-09 - under a week ago. Once
the initial monitoring I set up was completed, I left the cluster completely
idle until now. Checking the graph I made above, expanded to the last week:

![Idle Disk Load](/images/1weekIdle.png "that seems high")

I've circled 'blips' - or rather, cascading impact to the memory/CPU/etc that
gave me concern. I also circled the top line of the % memory RSS used -
you can see that as the number of IOPS **in progress** average spikes, there is
a corresponding spike in memory and cpu utilization that does not decrease
(more on this later).

This spike in non-IO utilization is normal in failure modes, the CPU utilization
percentage could get *lower* when throttling is occurring as the threads
performing IO are locked reading the filesystem, and do not consume cpu in a
blocking wait.

Looking at this chart however, the trigger isn't clear (throttle) but we can
determine a few things:

![IOPS Zoomed](/images/iops-zoom.png "Remember, this is an average across nodes")
![Disk busy zoom](/images/oms-dbusy-zoom.png "Why is disk busy so high")

1. We can see that the increase in memory usage/cpu/etc is directly correlated
   to a spike in IOPS against the OS disk.
2. We can see the average disk busy on the cluster is a minimum of 14% with
   minor upticks to 17-20% across the cluster

Based on this graph alone, you would be unable to diagnose the issue but you
could infer that something odd was occurring.

Given this issue is a generalized IaaS issue - lets change tacts.

## Azure Monitoring of the *nodepool*

Yes, I'm cheating since I know how this ends - but given the above view, what
in the portal would I set up as a brand-new-to-this user thinking about this?

In this case, I want to be able to see these values with **precision**
(stop. using. averages.) on the IaaS level. On Azure, this means shifting to the
Virtual Machine Scale sets view for the agentpool (aks-agentpool-57418505-vmss)
for the cluster.

This metrics view is more like normal systems administration/IaaS metrics views
tracking the host and VM instance level stats. Pretty straightforward then to
expand on the metrics I mapped above as well as a few host-specific ones.

The metrics on the chart include some 'surprise' contenders (yes, I'm cheating)
- in this case we want to use the OS disk metrics labeled "Preview" and ignore
the rest for now:

![OS disk metrics](/images/oms-dbusy-zoom.pngvmss-osdisk-metrics.png "Preview is the new GA")

And here are the key things I want to see in theory:

![VMSS V1](/images/something-is-weird.png "Waiiiiiit")

Ok, something is weird. We saw the data above that showed those spikes - lets
make it an area chart and zoom in on that rough window of time.

![VMSS V2](/images/vmss-v1-enh1 "Not doing it. Nope")

Ok, so we see a big, obvious spike - but if you look *real* close you can see
some blips in the OS Disk Queue length (I picked the one near Jan 12th):

![VMSS V2](/images/vmss-disk-queue "Oh hey")

The key metric here is OS Disk Queue Depth - from the chart we can see the
in load caused the disk queue to spike, high disk queue values will lead to
high latency - that makes sense.

Disk queue depth is a matter of debate. Cloud vendors implement their storage
optimizing for given constraints and workloads and optimizing the disk queue
depth is *highly* tied to the workload running on that device, the type of the
device, etc.

For example, this is [Azure's guidance on queue depth][aqd].

This means that while OS Disks Queue Depth (or length) can kinda tell you
something may have happened, we can see if you compare that to the custom chart
I built originally using the Container insights view showed a much larger impact
which we can't see clearly here in the node pool view either.

For more about Linux Disk I/O tuning - [this is a good overview][linuxio].

So we're not getting good signal, and something smells weird because I told you
it smells weird.

Building charts by hand on a per-node basis seems kinda not scalable and queue
depth as we can map it isn't a good indicator of what's to come. Let's move on.

Details on how (and which metrics) to track in the mitigation & cluster design
section.

[linuxio]: https://cromwell-intl.com/open-source/performance-tuning/disks.html
[aqd]: https://docs.microsoft.com/en-us/azure/virtual-machines/windows/premium-storage-performance#queue-depth