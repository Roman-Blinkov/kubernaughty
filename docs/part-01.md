# Diagnosing and chasing Kubernetes Kubernaughties

## Introduction

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
  means I probably don't know your cool tool.

Technical and other disclaimers:

- The commands and tools in this repository may or may not result in the
  wholesale destruction of your Kubernetes cluster should you run things
  without checking.
- If you are using a managed service (AKS, GCP, EKS) the stuff I go into here
  may or may not apply. Additionally, execution of some of these things may
  void your warranty / SLA / etc.

Finally:

I've worked for various cloud providers and enterprise / large scale vendors/etc
through the years. In all of those years I have tried to stay objective, fair,
honest, and candid. This means that while I work for Microsoft/Azure/AKS and
I will not disclose internal information, I do not redact or otherwise doctor
or change things due to my employer.

I have 3 dogs, 2 kiddos, grow plants, live in Colorado. I break things.

## Technical introduction

? overview of the issue - tbd nbd

## Setup

### Cluster details

- Provider: AKS
- Region: EastUS2
- Resource Group: kubernaughty
- Kubernetes version: 1.15.7
- 5 Nodes DS3_v2
  - 4 vCPU, 14 GiB RAM, 16 Data Disks, Max IOPS 12800, 28 GiB temp storage
- HTTP Application routing enabled
- Azure container monitoring enabled
- Azure CNI cluster


### Critical deets

- Agentpool: aks-agentpool-57418505-vmss
- Azure insights enabled via portal, agentpool required model update.

## Azure insights setup / review

I enabled Azure Container insights, if you select the different workbooks when
viewing the cluster you will see pre-created charts that show some of the key
base metrics you should be watching at all times for Kubernetes clusters:

![azure insights](/images/azureinsights1.png "Azure Insights")
![azure insights DiskIO](/images/insights-diskio.png "Azure Insights DiskIO")
![azure insights DiskIO2](/images/insights-diskio-2.png "Azure Insights DiskIO2")

Critical metrics here are:

- Kublet/
  - Overview By Operation Type
  - Overview By Node (% errors, operations, success rate)
- Node Disk IO/
  - % Disk Busy / Trend
  - % IOPS / Trend

If we look closer at the Node Disk IO we can already see some spikiness I would
keep my eye on:

![Why are the disks... so busy?](/images/whyisthediskbusy.png "Why is disk busy already so high?")

Hmmmmmmm.... which disks are busy?

![DEV SDA IS MADE OF PEOPLE](/images/osdiskuhoh.png "sda is the OS disk, the OS disk... is busy...")

**note**: Looks like the disks spike in usage during cluster creation,
          provisioning etc as one would expect. Disk busy across the cluster is
          averaging 0.17% - looking at the nodes each operating system disk is
          averaging 3.8%/4% up to 4.9% with node 0003 being highest with 4.94%
          average.

### How does Azure Insights run, previous?

Additional details on the daemonset, configuration, limits

## Azure Insights: Making a custom chart

Since I already know how this play ends (it's a tragedy Brent) - I'll show you
the chart you can build using Azure Insights (Metrics View) that will probably
save your ass **literally right now**:

![bling bling](/images/iops-busy-error-cpu-memory-brent.png "Watch me whip, watch me nae nae")

Key metrics I've plotted:

- Disk busy percentage
- IOPS in progress (hint!)
- Kubelet Operation error count (o_O)
- cpuUsagePercentage
- memoryRssPercentage (if Rss is an acronym (RSS), why isn't it capitalized?)
- memoryWorkingSetPercentage

[aks]: https://docs.microsoft.com/en-us/azure/aks/
[twitter]: https://twitter.com/jessenoller
