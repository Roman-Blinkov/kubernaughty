# Whats in the box?! (voiding the warranty)

- [Part 1: Introduction & Issue summary](/docs/part1-introduction-and-problem-description.md)
- [Part 2: Cluster Setup & Basic Monitoring](/docs/part2-basic-setup.md)
- [Part 3: hats in the box?! (voiding the warranty)](/docs/part3-whats-in-the-box)

Contents:

* [Introduction](#intro)

**WIP**

TBD - href
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

## Wait, Kubernetes isn't a PaaS...

Yeah, OK, I lied. I'm not done with you yet. Let me drop some painful hard
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
than say, an Azure App Service, Heroku, PKS, or Openshift.

The consequences of this 'difference in terms' is the difference between your
success with kube or your failure. If you go into your adoption thinking you
are going to hand kubectl, creds and the API server endpoint to your front line
application developers without **adding on all of the paas-like things you'll
need (CI/CD, app packaging, etc)** its going to be painful and slow.

There are no 'quick fixes' to changing the very nature of how you rationalize
and operate your applications at a global scale. Stop trying.

## Voiding the Warranty

In part 2 we left off with a lot of questions - given the issue summary, what
metrics could we begin to look at to know that this could be happening
(or other failure like this)?

Before we get started - let's double check the cluster to see what its been
up to (using my misleading chart):

![Idle Cluster util](/images/2-15-huh.png "Seems weird")

So. We have a cluster, and we have some nodes, and I'm a pre-cloud grumpy
engineer so the first thing I'm going to do is start SSH'ing into things.

### Enabling SSH

*In progress*

# Tools

[csshtools]: https://medium.com/@joantolos/cluster-ssh-tool-using-macos-a66930eeada6
