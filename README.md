# kubernaughty

This is a collection of documentation, how-tos, tools and other information on
debugging and identifying Kubernetes/container workload failures, performance
and reliability considerations.

Initially this investigation started as user-reported failures at the DNS,
networking and application levels, however through the analysis the actual causes
for these failures we due to severe resource saturation & contention, IO
throttling, kernel panics, etc. For an overview, see [Part 1: Summary][part1].

Through the investigation, I've discovered a lack of operational / systems
knowledge, tracking and general awareness of the worker nodes / linux hosts
that comprise kubernetes clusters (including filesystem incompatibility).

There are many gotchas, mud pits and blind spots running distributed systems,
and kubernetes is no different. My goal with this is to step through the past 20
years of my career (eg, showing everyone my mistakes and learnings from the
past).

Hopefully, this stuff helps you and your team.

>**This is an ongoing project / labor of love. It is not complete by any means**

## Roadmap

- [the rough project roadmap is here](https://github.com/jnoller/kubernaughty/projects/1)
- Issues, comments and suggestions can be filed in the [tracker](https://github.com/jnoller/kubernaughty/issues)

## Contents:

### Screencasts 

* [Demonstration of `helm install istio` trigging terminal IO latency](https://www.youtube.com/watch?v=Uk_MtHLvLcA)
* [`helm install istio` trigging terminal IO latency Part 2](https://www.youtube.com/watch?v=kueX1HZogQI) 

### Kubernaughty 1: IO saturation and throttling

* [Part 1: Introduction & Issue summary][part1]
* [Part 2: Cluster Setup & Basic Monitoring][part2]
* [Part 3: What's in the box?! (voiding the warranty)][part3]
* [Part 4: That's how you fail a container runtime?][part4]



[part1]: /docs/part1-introduction-and-problem-description.md
[part2]: /docs/part2-basic-setup.md
[part3]: /docs/part3-whats-in-the-box.md
[part4]: /docs/part-4-how-you-kill-a-container-runtime.md
