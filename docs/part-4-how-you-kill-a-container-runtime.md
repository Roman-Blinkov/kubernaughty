
# Thats how you kill a container runtime?

Contents:

- [Introduction](#intro)
- [The prometheus-operator chart?](#prop)
- [Analyzing the failed `helm install`](#fail)
  - [Install IOVisor/bcc](#bcc)
  - [Kubectl is made of container failures](#soylent)
  - [What does the pod say?](#podlogs)
- [Summary](#summary)

<a name="intro"></a>

# Introduction

Previously I outlined some of my short command aliases - but - just to be nice
I'll run through getting the credentials, and logging into the cluster:

```
jnoller@doge kubernaughty (master) $ -> (⎈ |lseriespewpew:default)$ az aks get-credentials -n kubernaughty
The behavior of this command has been altered by the following extension: aks-preview
Merged "kubernaughty" as current context in /Users/jnoller/.kube/config
jnoller@doge kubernaughty (master) $ -> (⎈ |kubernaughty:default)$ ctx
kubernaughty
lseriespewpew
jnoller@doge kubernaughty (master) $ -> (⎈ |kubernaughty:default)$ ctx kubernaughty
Switched to context "kubernaughty".
jnoller@doge kubernaughty (master) $ -> (⎈ |kubernaughty:default)$ k get no -o wide
NAME                                STATUS   ROLES   AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
aks-agentpool-57418505-vmss000000   Ready    agent   12d   v1.15.7   10.240.0.4     <none>        Ubuntu 16.04.6 LTS   4.15.0-1064-azure   docker://3.0.8
aks-agentpool-57418505-vmss000001   Ready    agent   12d   v1.15.7   10.240.0.35    <none>        Ubuntu 16.04.6 LTS   4.15.0-1064-azure   docker://3.0.8
aks-agentpool-57418505-vmss000002   Ready    agent   12d   v1.15.7   10.240.0.66    <none>        Ubuntu 16.04.6 LTS   4.15.0-1064-azure   docker://3.0.8
aks-agentpool-57418505-vmss000003   Ready    agent   12d   v1.15.7   10.240.0.97    <none>        Ubuntu 16.04.6 LTS   4.15.0-1064-azure   docker://3.0.8
aks-agentpool-57418505-vmss000004   Ready    agent   12d   v1.15.7   10.240.0.128   <none>        Ubuntu 16.04.6 LTS   4.15.0-1064-azure   docker://3.0.8
jnoller@doge kubernaughty (master) $ -> (⎈ |kubernaughty:default)$
```

Since the point here isn't to teach kubernetes - I'm going to assume for now
you're semi-familiar with it (it's sort of a big deal).

Right now, we have a mostly idle cluster, we have SSH, we have some metrics.

Lets install something - lets say... the prometheus-operator helm chart?

<a name="prop"></a>

## The prometheus-operator chart?

Why? How dare you question Oz! Seriously, good question. In part one I described
the issue (primary OS disk throttling due to quota) and the symptoms (node
failure). Obviously triggering the issue requires IO.

In the case of Kubernetes, you have a veritable poo-poo-platter of IO causing
things. Logging, monitoring, containers starting up, shutting down, network
traffic, more logging, some agent you have installed and:

*Every sidecar on the planet*

In this case, the [prometheus operator][pop] serves a dual purpose:

1. Deploying the full stack includes a lot of chatty containers
2. Bigger containers (the bigger the container, the worse the IO penalty)
3. The operator is fully HA, which means it should poke most of the nodes in the
   cluster.
4. The operator includes a whole bunch of critical metrics and reports for
   Kubernetes operators, we're going to want that.

### Enable the webhook

Depending on if you have Active Directory integration enabled, and what
version of kubernetes your AKS cluster is running, the authentication webhook
may need to be enabled on the worker node kubelets. You can do this by running:

```
command="sed -i 's/--authorization-mode=Webhook/--authorization-mode=Webhook --authentication-token-webhook=true/g' /etc/default/kubelet"
az vmss run-command invoke -g "${cluster_resource_group}" \
  -n "${cluster_scaleset}" \
  --instance "${vmss_instance_id}" \
  --command-id RunShellScript -o json --scripts "${command}" | jq -r '.value[].message'
```

But - I automated that - look in [`tools/enable-webhook`][tools], example:

```
jnoller@doge kubernaughty (master) $ -> (⎈ |kubernaughty:default)$ tools/enable-webhook Kubernaughty Kubernaughty
The behavior of this command has been altered by the following extension: aks-preview
Running command on cluster: Kubernaughty

RG: MC_kubernaughty_kubernaughty_eastus2

NRG: MC_kubernaughty_kubernaughty_eastus2

scaleset: aks-agentpool-57418505-vmss

Nodes:
aks-agentpool-57418505-vmss_0
aks-agentpool-57418505-vmss_1
aks-agentpool-57418505-vmss_2
aks-agentpool-57418505-vmss_3
aks-agentpool-57418505-vmss_4
    Command: sed -i 's/--authorization-mode=Webhook/--authorization-mode=Webhook --authentication-token-webhook=true/g' /etc/default/kubelet
```

With that we can now move on to being lazy and just mash the helm command:

```
jnoller@doge ~ $ -> (⎈ |kubernaughty:default)$ helm install prop stable/prometheus-operator
manifest_sorter.go:175: info: skipping unknown hook: "crd-install"
manifest_sorter.go:175: info: skipping unknown hook: "crd-install"
manifest_sorter.go:175: info: skipping unknown hook: "crd-install"
manifest_sorter.go:175: info: skipping unknown hook: "crd-install"
manifest_sorter.go:175: info: skipping unknown hook: "crd-install"
NAME: prop
LAST DEPLOYED: Wed Jan 29 17:33:20 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
The Prometheus Operator has been installed. Check its status by running:
  kubectl --namespace default get pods -l "release=prop"

Visit https://github.com/coreos/prometheus-operator for instructions on how
to create & configure Alertmanager and Prometheus instances using the Operator.
jnoller@doge ~ $ -> (⎈ |kubernaughty:default)$ k get pods --all-namespaces
NAMESPACE     NAME                                                              READY   STATUS    RESTARTS   AGE
default       alertmanager-prop-prometheus-operator-alertmanager-0              2/2     Running   0          88s
default       prometheus-prop-prometheus-operator-prometheus-0                  3/3     Running   1          79s
default       prop-grafana-74d59957f4-gwcxf                                     2/2     Running   0          97s
default       prop-kube-state-metrics-74f86d7949-8ntwc                          1/1     Running   0          97s
default       prop-prometheus-node-exporter-54qr6                               1/1     Running   0          97s
default       prop-prometheus-node-exporter-999mt                               1/1     Running   0          97s
default       prop-prometheus-node-exporter-jz5wc                               1/1     Running   0          97s
default       prop-prometheus-node-exporter-lt744                               1/1     Running   0          97s
default       prop-prometheus-node-exporter-w8n6b                               1/1     Running   0          97s
default       prop-prometheus-operator-operator-6bc6fd7c9d-wvkht                2/2     Running   0          97s
default       sshjump                                                           1/1     Running   0          7d1h
kube-system   addon-http-application-routing-default-http-backend-574dcb68t9b   1/1     Running   0          19d
kube-system   addon-http-application-routing-external-dns-7cbc99cb46-zcc4q      1/1     Running   0          19d
kube-system   addon-http-application-routing-nginx-ingress-controller-64k24bl   1/1     Running   0          19d
kube-system   azure-cni-networkmonitor-4wflf                                    1/1     Running   0          19d
kube-system   azure-cni-networkmonitor-78wf2                                    1/1     Running   0          19d
```

Yay! Everything just worked!

> Narrator: It in fact, had not worked

I'm cheating. I knew that the command above would cause the **container
runtime** and kubelets on the node to begin failing. This is of course due to
the IOPS throttling on the worker nodes, or sunspots.

<a name="fail"></a>

## Analyzing the failed `helm install`

You did not see any errors above simply due to the fact that Kubernetes and Docker
did their job. They failed to schedule and run, so they got restarted. Except
**that should not happen on a brand new cluster, or ANY** due to this issue.

So, before we go further, let's analyze this a little. I have SSH for a reason.

Here is the failure in 1080p glory (first screen recording, sad face):

[![CRFAIL](http://img.youtube.com/vi/eFgo9OjQeMo/0.jpg)](https://www.youtube.com/watch?v=eFgo9OjQeMo "Woops")

First, let's look at the first hint that something went sideways - here's a
snippet from the Kubelet log:

```
Jan 30 23:23:40 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:23:40.383506    4382 container_manager_linux.go:457] [ContainerManager]: Discovered runtime cgroups name: /system.slice/docker.service
Jan 30 23:24:31 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:24:31.646552    4382 log.go:172] http: superfluous response.WriteHeader call from k8s.io/kubernetes/vendor/k8s.io/apiserver/pkg/server/httplog.(*respLogger).WriteHeader (httplog.go:184)
Jan 30 23:25:07 aks-agentpool-57418505-vmss000000 kubelet[4382]: W0130 23:25:07.241486    4382 reflector.go:302] object-"kube-system"/"azure-ip-masq-agent-config": watch of *v1.ConfigMap ended with: too old resource version: 3244649 (3245058)
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.075369    4382 kubelet.go:1888] SyncLoop (ADD, "api"): "prop-prometheus-operator-operator-6bc6fd7c9d-d9qz4_default(47fba903-9c81-4c87-ab6c-9794e0829414)"
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.189935    4382 reconciler.go:203] operationExecutor.VerifyControllerAttachedVolume started for volume "tls-proxy-secret" (UniqueName: "kubernetes.io/secret/47fba903-9c81-4c87-ab6c-9794e0829414-tls-proxy-secret") pod "prop-prometheus-operator-operator-6bc6fd7c9d-d9qz4" (UID: "47fba903-9c81-4c87-ab6c-9794e0829414")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.189984    4382 reconciler.go:203] operationExecutor.VerifyControllerAttachedVolume started for volume "prop-prometheus-operator-operator-token-2jfrz" (UniqueName: "kubernetes.io/secret/47fba903-9c81-4c87-ab6c-9794e0829414-prop-prometheus-operator-operator-token-2jfrz") pod "prop-prometheus-operator-operator-6bc6fd7c9d-d9qz4" (UID: "47fba903-9c81-4c87-ab6c-9794e0829414")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.237446    4382 kubelet.go:1888] SyncLoop (ADD, "api"): "prop-prometheus-node-exporter-q7fvn_default(8861c2f4-e635-43d3-a6af-f826801ed969)"
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.290337    4382 reconciler.go:248] operationExecutor.MountVolume started for volume "tls-proxy-secret" (UniqueName: "kubernetes.io/secret/47fba903-9c81-4c87-ab6c-9794e0829414-tls-proxy-secret") pod "prop-prometheus-operator-operator-6bc6fd7c9d-d9qz4" (UID: "47fba903-9c81-4c87-ab6c-9794e0829414")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.290387    4382 reconciler.go:248] operationExecutor.MountVolume started for volume "prop-prometheus-operator-operator-token-2jfrz" (UniqueName: "kubernetes.io/secret/47fba903-9c81-4c87-ab6c-9794e0829414-prop-prometheus-operator-operator-token-2jfrz") pod "prop-prometheus-operator-operator-6bc6fd7c9d-d9qz4" (UID: "47fba903-9c81-4c87-ab6c-9794e0829414")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.298654    4382 operation_generator.go:713] MountVolume.SetUp succeeded for volume "tls-proxy-secret" (UniqueName: "kubernetes.io/secret/47fba903-9c81-4c87-ab6c-9794e0829414-tls-proxy-secret") pod "prop-prometheus-operator-operator-6bc6fd7c9d-d9qz4" (UID: "47fba903-9c81-4c87-ab6c-9794e0829414")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.304311    4382 operation_generator.go:713] MountVolume.SetUp succeeded for volume "prop-prometheus-operator-operator-token-2jfrz" (UniqueName: "kubernetes.io/secret/47fba903-9c81-4c87-ab6c-9794e0829414-prop-prometheus-operator-operator-token-2jfrz") pod "prop-prometheus-operator-operator-6bc6fd7c9d-d9qz4" (UID: "47fba903-9c81-4c87-ab6c-9794e0829414")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.390753    4382 reconciler.go:203] operationExecutor.VerifyControllerAttachedVolume started for volume "sys" (UniqueName: "kubernetes.io/host-path/8861c2f4-e635-43d3-a6af-f826801ed969-sys") pod "prop-prometheus-node-exporter-q7fvn" (UID: "8861c2f4-e635-43d3-a6af-f826801ed969")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.390803    4382 reconciler.go:203] operationExecutor.VerifyControllerAttachedVolume started for volume "prop-prometheus-node-exporter-token-xkddz" (UniqueName: "kubernetes.io/secret/8861c2f4-e635-43d3-a6af-f826801ed969-prop-prometheus-node-exporter-token-xkddz") pod "prop-prometheus-node-exporter-q7fvn" (UID: "8861c2f4-e635-43d3-a6af-f826801ed969")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.390899    4382 reconciler.go:203] operationExecutor.VerifyControllerAttachedVolume started for volume "proc" (UniqueName: "kubernetes.io/host-path/8861c2f4-e635-43d3-a6af-f826801ed969-proc") pod "prop-prometheus-node-exporter-q7fvn" (UID: "8861c2f4-e635-43d3-a6af-f826801ed969")
```

This shows that the deployment was picked up - and now the pods/containers etc are
starting up. This causes the load on the node to spike, and then:

```
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.472829    4382 kuberuntime_manager.go:404] No sandbox for pod "prop-prometheus-operator-operator-6bc6fd7c9d-d9qz4_default(47fba903-9c81-4c87-ab6c-9794e0829414)" can be found. Need to start a new one
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.491240    4382 reconciler.go:248] operationExecutor.MountVolume started for volume "sys" (UniqueName: "kubernetes.io/host-path/8861c2f4-e635-43d3-a6af-f826801ed969-sys") pod "prop-prometheus-node-exporter-q7fvn" (UID: "8861c2f4-e635-43d3-a6af-f826801ed969")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.491289    4382 reconciler.go:248] operationExecutor.MountVolume started for volume "prop-prometheus-node-exporter-token-xkddz" (UniqueName: "kubernetes.io/secret/8861c2f4-e635-43d3-a6af-f826801ed969-prop-prometheus-node-exporter-token-xkddz") pod "prop-prometheus-node-exporter-q7fvn" (UID: "8861c2f4-e635-43d3-a6af-f826801ed969")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.491318    4382 reconciler.go:248] operationExecutor.MountVolume started for volume "proc" (UniqueName: "kubernetes.io/host-path/8861c2f4-e635-43d3-a6af-f826801ed969-proc") pod "prop-prometheus-node-exporter-q7fvn" (UID: "8861c2f4-e635-43d3-a6af-f826801ed969")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.491368    4382 operation_generator.go:713] MountVolume.SetUp succeeded for volume "proc" (UniqueName: "kubernetes.io/host-path/8861c2f4-e635-43d3-a6af-f826801ed969-proc") pod "prop-prometheus-node-exporter-q7fvn" (UID: "8861c2f4-e635-43d3-a6af-f826801ed969")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.491567    4382 operation_generator.go:713] MountVolume.SetUp succeeded for volume "sys" (UniqueName: "kubernetes.io/host-path/8861c2f4-e635-43d3-a6af-f826801ed969-sys") pod "prop-prometheus-node-exporter-q7fvn" (UID: "8861c2f4-e635-43d3-a6af-f826801ed969")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.499946    4382 operation_generator.go:713] MountVolume.SetUp succeeded for volume "prop-prometheus-node-exporter-token-xkddz" (UniqueName: "kubernetes.io/secret/8861c2f4-e635-43d3-a6af-f826801ed969-prop-prometheus-node-exporter-token-xkddz") pod "prop-prometheus-node-exporter-q7fvn" (UID: "8861c2f4-e635-43d3-a6af-f826801ed969")
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:27:56.555078    4382 kuberuntime_manager.go:404] No sandbox for pod "prop-prometheus-node-exporter-q7fvn_default(8861c2f4-e635-43d3-a6af-f826801ed969)" can be found. Need to start a new one
Jan 30 23:27:57 aks-agentpool-57418505-vmss000000 kubelet[4382]: 2020/01/30 23:27:57 [6925] [cni-ipam] Plugin azure-vnet-ipam version v1.0.29.
```

The deployment started at ~23:23 - the pods on this node (node 0 of a 5 node) are
really unhappy:

```
Jan 30 23:28:19 aks-agentpool-57418505-vmss000000 kubelet[4382]: 2020/01/30 23:28:19 [8711] [cni-ipam] Plugin stopped.
Jan 30 23:28:20 aks-agentpool-57418505-vmss000000 kubelet[4382]: W0130 23:28:20.210877    4382 pod_container_deletor.go:75] Container "2dcfc67a6a4774409a7200f91a13dd4fd37bd7d7723cc33207fe9817c981279e" not found in pod's containers
Jan 30 23:28:21 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:28:21.135911    4382 kubelet_pods.go:1090] Killing unwanted pod "prop-prometheus-operator-admission-patch-tbln5"
Jan 30 23:28:40 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:28:40.384030    4382 container_manager_linux.go:457] [ContainerManager]: Discovered runtime cgroups name: /system.slice/docker.service
Jan 30 23:33:15 aks-agentpool-57418505-vmss000000 kubelet[4382]: W0130 23:33:15.597465    4382 reflector.go:302] object-"kube-system"/"container-azm-ms-agentconfig": watch of *v1.ConfigMap ended with: too old resource version: 3245886 (3246372)
Jan 30 23:33:40 aks-agentpool-57418505-vmss000000 kubelet[4382]: I0130 23:33:40.384564    4382 container_manager_linux.go:457] [ContainerManager]: Discovered runtime cgroups name: /system.slice/docker.service
```

These errors continue until 23:27:56 until 23:28:17 - so, about a **minute** of
failed pods / starting with an idle 5 node cluster running a helm install.

Looking at the docker logs:

```
Jan 30 23:27:56 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:27:56.558110997Z" level=warning msg="Published ports are discarded when using host network mode"
Jan 30 23:27:57 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:27:57.048116177Z" level=warning msg="Published ports are discarded when using host network mode"
Jan 30 23:27:57 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:27:57.175479212Z" level=info msg="shim containerd-shim started" address="/containerd-shim/moby/3b800a25b4f64c6b6f1d9e4590506f35497a6c7f72c1578f24f69c230bc2ae01/shim.sock" debug=false pid=6774
Jan 30 23:27:57 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:27:57.197863994Z" level=info msg="shim containerd-shim started" address="/containerd-shim/moby/519700e72cf8dc28c2bdba3e3e7465efd5450bf3a63b1b24452c931f36a304e3/shim.sock" debug=false pid=6790
Jan 30 23:27:57 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:27:57.973770996Z" level=info msg="shim containerd-shim started" address="/containerd-shim/moby/c2ba397c175d53933d5b8abeabd67a07ba7bc8c879d74e70fb21d1f8442ffe4d/shim.sock" debug=false pid=6987
Jan 30 23:27:58 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:27:58.102205140Z" level=info msg="shim containerd-shim started" address="/containerd-shim/moby/c85edf948f566b49751ff53400324f07ebd0adedb00747fdeb3ed25616b7ec42/shim.sock" debug=false pid=7022
Jan 30 23:27:58 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:27:58.597771465Z" level=info msg="shim containerd-shim started" address="/containerd-shim/moby/9cb23425454e1b240a6d0abed082c6508161d651b6ec4235dae4f5b669c965b7/shim.sock" debug=false pid=7123
Jan 30 23:28:14 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:14.118847652Z" level=info msg="shim containerd-shim started" address="/containerd-shim/moby/fb9452a1c6fae7ea7effabae5266f0a9122e4f51b6eacd9f40f4a0aee1f7b549/shim.sock" debug=false pid=7954
Jan 30 23:28:14 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:14.900389401Z" level=info msg="shim containerd-shim started" address="/containerd-shim/moby/669347180a9aefac468e71cb845b439b1b7fc1fb13c0a975a59bed56a38f528a/shim.sock" debug=false pid=8124
Jan 30 23:28:15 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:15.202303554Z" level=info msg="shim reaped" id=669347180a9aefac468e71cb845b439b1b7fc1fb13c0a975a59bed56a38f528a
Jan 30 23:28:15 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:15.212570837Z" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Jan 30 23:28:15 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:15.212677538Z" level=warning msg="669347180a9aefac468e71cb845b439b1b7fc1fb13c0a975a59bed56a38f528a cleanup: failed to unmount IPC: umount /var/lib/docker/containers/669347180a9aefac468e71cb845b439b
Jan 30 23:28:16 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:16.383424549Z" level=info msg="shim reaped" id=fb9452a1c6fae7ea7effabae5266f0a9122e4f51b6eacd9f40f4a0aee1f7b549
Jan 30 23:28:16 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:16.393830634Z" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Jan 30 23:28:17 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:17.503209646Z" level=info msg="shim containerd-shim started" address="/containerd-shim/moby/2dcfc67a6a4774409a7200f91a13dd4fd37bd7d7723cc33207fe9817c981279e/shim.sock" debug=false pid=8412
Jan 30 23:28:19 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:19.220238496Z" level=info msg="shim reaped" id=2dcfc67a6a4774409a7200f91a13dd4fd37bd7d7723cc33207fe9817c981279e
Jan 30 23:28:19 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:19.230447279Z" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.287713968Z" level=info msg="shim reaped" id=9cb23425454e1b240a6d0abed082c6508161d651b6ec4235dae4f5b669c965b7
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.300224969Z" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.300407170Z" level=warning msg="9cb23425454e1b240a6d0abed082c6508161d651b6ec4235dae4f5b669c965b7 cleanup: failed to unmount IPC: umount /var/lib/docker/containers/9cb23425454e1b240a6d0abed082c650
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.303212593Z" level=info msg="shim reaped" id=c85edf948f566b49751ff53400324f07ebd0adedb00747fdeb3ed25616b7ec42
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.303797898Z" level=info msg="shim reaped" id=c2ba397c175d53933d5b8abeabd67a07ba7bc8c879d74e70fb21d1f8442ffe4d
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.311279058Z" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.311396759Z" level=warning msg="c85edf948f566b49751ff53400324f07ebd0adedb00747fdeb3ed25616b7ec42 cleanup: failed to unmount IPC: umount /var/lib/docker/containers/c85edf948f566b49751ff53400324f07
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.313324875Z" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.313622777Z" level=warning msg="c2ba397c175d53933d5b8abeabd67a07ba7bc8c879d74e70fb21d1f8442ffe4d cleanup: failed to unmount IPC: umount /var/lib/docker/containers/c2ba397c175d53933d5b8abeabd67a07
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.806102849Z" level=info msg="shim reaped" id=3b800a25b4f64c6b6f1d9e4590506f35497a6c7f72c1578f24f69c230bc2ae01
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.816161730Z" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.911518699Z" level=info msg="shim reaped" id=519700e72cf8dc28c2bdba3e3e7465efd5450bf3a63b1b24452c931f36a304e3
Jan 31 14:23:35 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-31T14:23:35.921565480Z" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
```

I guess `failed to unmount IPC` is bad? But what we can see here is a 1:1 mapping
to the container PLEG errors we see in the kublet logs.

While I'm here - you're probably wondering where / why / what logging goes,
since logging trips IO issues too, well:

```
root@aks-agentpool-57418505-vmss000000:/var/log# ls pods/
default_debug-dns-xgxzt_a167a66c-eaf9-4af0-955f-0f2faafd8b74                     kube-system_azure-ip-masq-agent-stdbz_ce64293d-3224-4f55-8861-399752fff5c3  kube-system_omsagent-57s9q_5a6f23c5-1108-44cd-a70c-05bd19638c30
kube-system_azure-cni-networkmonitor-kvnfk_82c42285-cba8-43f8-869f-11fa53410a1c  kube-system_kube-proxy-76mqg_92517749-5101-465e-b7f3-adb5c03076cd           kube-system_tunnelfront-6f6b94fd4d-d2gpl_be617390-4231-4105-8270-4f9e19298741
root@aks-agentpool-57418505-vmss000000:/var/log#
root@aks-agentpool-57418505-vmss000000:/var/log# less pods/kube-system_kube-proxy-76mqg_92517749-5101-465e-b7f3-adb5c03076cd/kube-proxy/0.log
```

<a name="bcc"></a>

### Install IOVisor/bcc

```
root@aks-agentpool-57418505-vmss000000:~# apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4052245BD4284CDD
Executing: /tmp/tmp.Nn8TzI1cqW/gpg.1.sh --keyserver
....
Fetched 3,616 B in 0s (5,873 B/s)
Reading package lists... Done
root@aks-agentpool-57418505-vmss000000:~# sudo apt-get install bcc-tools libbcc-examples linux-headers-$(uname -r)
Reading package lists... Done
Building dependency tree
root@aks-agentpool-57418505-vmss000000:~# export PATH=$PATH:/usr/share/bcc/tools
```

In addition to watching the logs, I was also using the `ext4slower` from the
[IOVisor][bcc] project. This gives us a handy list of processes making IO calls
in my case, I want anything greated than 1ms of IO latency. This only shows calls
that exceed the 1ms threshold.

The second to the last column - LAT(ms) is key - thats operations latency in
milliseconds. IO latency above a few milliseconds in anything but very busy
systems should be a warning, if the system still works (*stares at databases*).

```
root@aks-agentpool-57418505-vmss000000:~# ext4slower 1
Tracing ext4 operations slower than 1 ms
TIME     COMM           PID    T BYTES   OFF_KB   LAT(ms) FILENAME
23:23:40 systemd-journa 4449   S 0       0          60.47 system.journal
23:23:40 systemd-journa 4449   S 0       0           7.44 system.journal
23:23:40 systemd-journa 4449   S 0       0           7.45 system.journal
23:25:01 logrotate      1568   S 0       0          67.33 status.tmp
23:25:01 logrotate      1576   S 0       0          16.09 omsagent-status.tmp
23:27:56 kubelet        4382   S 0       0          74.80 .179901148
23:27:56 kubelet        4382   S 0       0           9.25 .557434507
23:27:56 kubelet        4382   S 0       0          11.13 .261377646
23:27:56 dockerd        3349   S 0       0          96.40 .tmp-hostconfig.json259118070
23:27:56 dockerd        3349   S 0       0          96.41 .tmp-hostconfig.json982573277
23:27:56 dockerd        3349   S 0       0           6.54 .tmp-hostconfig.json513904481
23:27:56 dockerd        3349   S 0       0           6.53 .tmp-hostconfig.json353358218
23:27:56 dockerd        3349   S 0       0          13.24 .tmp-config.v2.json322732311
23:27:56 dockerd        3349   S 0       0          13.28 .tmp-config.v2.json754987672
23:27:57 dockerd        3349   S 0       0          41.12 .tmp-hostconfig.json447588411
23:27:57 dockerd        3349   S 0       0          46.86 .tmp-hostconfig.json819403813
23:27:57 dockerd        3349   S 0       0          18.68 .tmp-config.v2.json543133516
23:27:57 dockerd        3349   S 0       0          20.02 .tmp-config.v2.json115225182
23:27:57 kubelet        4382   S 0       0          19.30 .220796802
23:27:57 kubelet        4382   S 0       0          10.33 .207302393
23:27:57 dockerd        3349   S 0       0          11.92 local-kv.db
23:27:57 dockerd        3349   S 0       0           5.67 local-kv.db
23:27:57 dockerd        3349   S 0       0           3.29 local-kv.db
23:27:57 dockerd        3349   S 0       0           3.18 local-kv.db
23:27:57 dockerd        3349   S 0       0           3.47 local-kv.db
...
23:27:57 containerd     3375   S 0       0           3.13 meta.db
23:27:57 dockerd        3349   S 0       0          11.28 local-kv.db
23:27:57 dockerd        3349   S 0       0          16.23 .tmp-hostconfig.json310990964
23:27:57 dockerd        3349   S 0       0           5.35 local-kv.db
23:27:57 dockerd        3349   S 0       0          13.22 .tmp-config.v2.json297371433
23:27:57 dockerd        3349   S 0       0          44.98 .tmp-hostconfig.json688939843
23:27:57 dockerd        3349   S 0       0          36.05 .tmp-hostconfig.json742202989
23:27:57 dockerd        3349   S 0       0          16.36 .tmp-hostconfig.json849349927
23:27:57 dockerd        3349   S 0       0          19.92 .tmp-config.v2.json172542406
23:27:57 dockerd        3349   S 0       0          28.27 .tmp-config.v2.json461213416
23:27:57 dpkg-query     6932   R 627186  0           2.52 status
23:27:57 dockerd        3349   S 0       0         125.00 .tmp-hostconfig.json378595825
23:27:57 dockerd        3349   S 0       0          57.72 .tmp-hostconfig.json153006748
23:27:57 dockerd        3349   S 0       0          23.45 .tmp-config.v2.json614788698
23:27:57 dockerd        3349   S 0       0          15.47 .tmp-hostconfig.json302090798
23:27:57 containerd     3375   S 0       0           9.51 meta.db
23:27:57 containerd     3375   S 0       0          12.02 meta.db
23:27:57 dockerd        3349   S 0       0          25.16 .tmp-config.v2.json348468555
23:27:57 containerd     3375   S 0       0          12.02 meta.db
23:27:57 containerd     3375   S 0       0           3.30 meta.db
23:27:57 containerd     3375   S 0       0           3.50 meta.db
23:27:57 containerd     3375   S 0       0           3.11 meta.db
23:27:58 dockerd        3349   S 0       0          41.70 .tmp-hostconfig.json336390544
23:27:58 dockerd        3349   S 0       0          11.11 .tmp-config.v2.json108298677
23:27:58 containerd     3375   S 0       0           3.52 meta.db
23:27:58 containerd     3375   S 0       0           3.23 meta.db
...
23:27:58 dockerd        3349   S 0       0          24.39 .tmp-hostconfig.json020335233
23:27:58 dockerd        3349   S 0       0          10.10 .tmp-config.v2.json486477098
23:27:58 dpkg-query     7189   R 2168438 0           1.18 azure-cli.list
23:28:08 dockerd        3349   W 139     8242        1.30 82ef6610185c7ac4ddecad92361cb5fb
23:28:13 kubelet        4382   S 0       0          68.91 .896585220
23:28:13 dockerd        3349   W 215     8249        1.45 82ef6610185c7ac4ddecad92361cb5fb
23:28:13 dockerd        3349   S 0       0          80.04 .tmp-hostconfig.json254387692
23:28:13 dockerd        3349   S 0       0          12.33 .tmp-hostconfig.json239019006
23:28:13 dockerd        3349   S 0       0           9.95 .tmp-config.v2.json451152475
23:28:14 dockerd        3349   S 0       0          12.35 .tmp-hostconfig.json396275168
23:28:14 dockerd        3349   S 0       0          12.80 .tmp-config.v2.json922837829
23:28:14 kubelet        4382   S 0       0           9.80 .243008982
23:28:14 dockerd        3349   S 0       0           4.44 local-kv.db
23:28:14 dockerd        3349   S 0       0           3.30 local-kv.db
...
23:28:15 dockerd        3349   S 0       0          28.70 .tmp-hostconfig.json049690385
23:28:15 dockerd        3349   S 0       0          24.95 .tmp-config.v2.json488392698
23:28:15 dpkg-query     8224   R 2168438 0           1.23 azure-cli.list
23:28:15 containerd     3375   S 0       0          34.55 meta.db
23:28:15 containerd     3375   S 0       0           3.15 meta.db
23:28:15 dockerd        3349   S 0       0          11.02 .tmp-hostconfig.json247584107
23:28:15 dockerd        3349   S 0       0           9.96 .tmp-config.v2.json716777276
23:28:16 dockerd        3349   S 0       0          13.80 .tmp-hostconfig.json606591701
23:28:16 dockerd        3349   S 0       0          17.78 .tmp-config.v2.json082123214
23:28:16 dockerd        3349   S 0       0           3.90 local-kv.db
...
23:28:19 dockerd        3349   S 0       0          11.35 .tmp-hostconfig.json063497356
23:28:19 dockerd        3349   S 0       0          11.76 .tmp-config.v2.json811818913
23:28:21 dockerd        3349   R 7505    0           2.15 8f6ef57bc2d27df23f534f4b0c97b64b
23:28:21 dockerd        3349   S 0       0          56.27 .tmp-hostconfig.json745516958
23:28:21 dockerd        3349   S 0       0          10.73 .tmp-config.v2.json769214075
23:28:21 dockerd        3349   S 0       0          42.24 .tmp-hostconfig.json658346112
23:28:21 dockerd        3349   S 0       0           9.74 .tmp-config.v2.json821022309
23:28:21 dockerd        3349   S 0       0          43.82 .tmp-hostconfig.json896023986
23:28:21 dockerd        3349   S 0       0          15.76 .tmp-config.v2.json648744927
23:28:40 systemd-journa 4449   S 0       0         276.97 system.journal
23:28:40 systemd-journa 4449   S 0       0           8.65 system.journal
23:28:40 systemd-journa 4449   S 0       0           8.08 system.journal
23:29:56 kubectl        11532  S 0       0         152.64 632231914
23:29:56 kubectl        11532  S 0       0          10.46 277321793
23:29:57 kubectl        11532  S 0       0          10.10 006965769
...
23:29:57 kubectl        11532  S 0       0          15.01 337063767
23:29:57 kubectl        11532  S 0       0          13.66 711327946
23:29:57 kubectl        11532  S 0       0          13.63 759944844
23:29:57 kubectl        11532  S 0       0          11.98 566813307
23:30:01 logrotate      11698  S 0       0          25.60 status.tmp
23:30:01 logrotate      11712  S 0       0          19.20 omsagent-status.tmp
23:30:01 logrotate      11701  S 0       0          30.71 status
23:30:01 logrotate      11713  S 0       0          18.84 omi-logrotate.status.tmp
23:30:30 kubectl        12534  S 0       0         138.95 254012105
23:30:30 kubectl        12534  S 0       0          11.79 421493140
23:31:02 kubectl        13456  S 0       0          12.84 999061704
23:31:02 kubectl        13456  S 0       0           9.76 938884487
```

<a name="soylent"></a>
### Kubectl is made of container failures

Oh - before I forget, if you run `ext4slower` after you have some workload
running on the cluster you should expect `kubectl` to pop up as a high IO
latency entity:

```
root@aks-agentpool-57418505-vmss000000:~# ext4slower 1
Tracing ext4 operations slower than 1 ms
TIME     COMM           PID    T BYTES   OFF_KB   LAT(ms) FILENAME
00:20:35 kubectl        97517  S 0       0          70.23 854679480
00:20:35 kubectl        97517  S 0       0          11.87 847029175
00:21:07 kubectl        98436  S 0       0          10.44 961150455
00:21:07 kubectl        98436  S 0       0          10.31 671622890
```

This output makes sense, those file names are containers - when the helm
install command runs and the pods are scheduled the container, kube and logging
IO all spike. This in turn triggers the Azure quotas on the OS disk for each
worker injecting possibly hundreds of millisecond of disk latency leading the
processes and pods to fail.

Remember the logs?

```
kuberuntime_manager.go:404] No sandbox for pod "prop-prometheus-node-exporter-q7fvn_default(8861c2f4-e635-43d3-a6af-f826801ed969)" can be found. Need to start a new one
```

```
Jan 30 23:28:16 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:16.383424549Z" level=info msg="shim reaped" id=fb9452a1c6fae7ea7effabae5266f0a9122e4f51b6eacd9f40f4a0aee1f7b549
Jan 30 23:28:16 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:16.393830634Z" level=info msg="ignoring event" module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Jan 30 23:28:17 aks-agentpool-57418505-vmss000000 dockerd[3349]: time="2020-01-30T23:28:17.503209646Z" level=info msg="shim containerd-shim started" address="/containerd-shim/moby/2dcfc67a6a4774409a7200f91a13dd4fd37bd7d7723cc33207fe9817c981279e/shim.sock" debug=false pid=8412
```

Why do you need a new one bro?

<a name="podlogs"></a>

### What does the pod say?

Well - here's the rub. We're dealing with the logs of a container - this means
that the perspective is inverted. What do I mean? The processes and kernel
within that container act and behaver as if they are normal processes reading
off the filesystem.

This means you won't see a ton of IOWait or other things in many cases, but you
will get a lot of 'unable to read', 'file does not exist' - this is because
the latency in the underlying VM is high enough the overlayfs calls to read the
file are timing out.

As we see here:

```
jnoller@doge ~ $ -> (⎈ |kubernaughty:default)$ k logs prometheus-prop-prometheus-operator-prometheus-0 --all-containers --previous
...
level=info ts=2020-01-30T23:28:18.283Z caller=manager.go:814 component="rule manager" msg="Stopping rule manager..."
level=info ts=2020-01-30T23:28:18.283Z caller=manager.go:820 component="rule manager" msg="Rule manager stopped"
level=info ts=2020-01-30T23:28:18.283Z caller=main.go:556 msg="Scrape manager stopped"
level=info ts=2020-01-30T23:28:18.294Z caller=notifier.go:602 component=notifier msg="Stopping notification manager..."
level=info ts=2020-01-30T23:28:18.294Z caller=main.go:727 msg="Notifier manager stopped"
level=error ts=2020-01-30T23:28:18.294Z caller=main.go:736 err="error loading config from \"/etc/prometheus/config_out/prometheus.env.yaml\": couldn't load configuration (--config.file=\"/etc/prometheus/config_out/prometheus.env.yaml\"): open /etc/prometheus/config_out/prometheus.env.yaml: no such file or directory"
Error from server (BadRequest): previous terminated container "prometheus-config-reloader" in pod "prometheus-prop-prometheus-operator-prometheus-0" not found
```

There you have it - from the view of the daemon running within the container,
it could not fstat() the file (running eBPF inside the container here would be
nice, maybe I will do that).

<a name="summary"></a>

## Summary and `Disk Busy/Queue is a lie`

Let's look at the metrics for that window of time - notice anything weird? Like:

1. Why doesn't the disk busy average actually show the issue (its a bad metric,
   and an average, and there's no cap)
2. Why is the IOPS trend so low? (lies damned lies and metrics)
3. No, really - why don't they match (you should know why now.)

![Disk Busy on nodes](/images/p4-diskbusyspike.png "I'm really tired.")
![Disk iops on nodes](/images/p4-diskbusy-iops.png "I'm really tired still.")

What we see from these is this - the IOPS and disk busy / queue metrics you're
looking at are presented at the *host* level (the throttle is triggering on
the OS disk - /dev/sda), and don't really represent the metric you need which is
**saturation**.

The next part will walk though:

1. Connecting the dots (with BPF, monitoring and love)
2. Re-creating total node failure
3. Maybe a container running BPF tools so we can see what the container in the
   container in the container sees.

[Part 5: tbd][part5]

[part5]: /README.md

[pop]: https://github.com/coreos/prometheus-operator
[pophelm]: https://github.com/helm/charts/tree/master/stable/prometheus-operator
[debugp]: https://github.com/slack/k8s-debug-pod
[bcc]: https://github.com/iovisor/bcc
[tools]: https://github.com/jnoller/kubernaughty/tree/master/tools
