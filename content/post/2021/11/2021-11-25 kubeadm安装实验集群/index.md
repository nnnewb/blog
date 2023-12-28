---
title: "kubeadm安装实验集群记录"
slug: kubernetes-manually-install-by-kubeadm
date: 2021-11-25 14:31:00
categories:
- kubernetes
tags:
- kubernetes
- linux
---
## 前言

好吧，如果仔细想想就会发现不管是 k3s 还是 ucloud 上的 k8s ，都没有一个是自己手动配置好的。虽说并不是至关重要的，但手动用 kubeadm 装一次 kubernetes 总不会有什么坏处。顺手做个笔记。参考资料列出如下。

- https://kubernetes.io/zh/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- https://mirrors.tuna.tsinghua.edu.cn/help/kubernetes/
- https://computingforgeeks.com/deploy-kubernetes-cluster-on-ubuntu-with-kubeadm/

## 系统配置

正式安装之前先确认一些系统级配置。

### swapoff

简单的做法是 `sudo swapoff -a` 即可。之后改 `fstab` 把 `swap` 分区关掉。

### iptables检查桥接流量

用 `lsmod | grep bf_netfitler` 检查有没有启用 `bf_netfilter` 模块，如果没有输出的话说明没加载，执行下面的命令。

```shell
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
```

会在 `/etc/modules-load.d` 下添加一个模块自动加载的配置。

```shell
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
```

再在 `/etc/sysctl.d/` 下添加一个配置，允许 `iptables` 查看桥接流量。

然后用 `sysctl` 重载配置。

```shell
sudo sysctl --system
```

### 端口

控制平面节点的端口清单，如果有本机防火墙的话需要开放下面的端口。

| 协议 | 方向 | 端口范围  | 作用                    | 使用者                       |
| ---- | ---- | --------- | ----------------------- | ---------------------------- |
| TCP  | 入站 | 6443      | Kubernetes API 服务器   | 所有组件                     |
| TCP  | 入站 | 2379-2380 | etcd 服务器客户端 API   | kube-apiserver, etcd         |
| TCP  | 入站 | 10250     | Kubelet API             | kubelet 自身、控制平面组件   |
| TCP  | 入站 | 10251     | kube-scheduler          | kube-scheduler 自身          |
| TCP  | 入站 | 10252     | kube-controller-manager | kube-controller-manager 自身 |

工作节点的端口清单，如果有本机防火墙的话需要开放下面的端口。

| 协议 | 方向 | 端口范围    | 作用           | 使用者                     |
| ---- | ---- | ----------- | -------------- | -------------------------- |
| TCP  | 入站 | 10250       | Kubelet API    | kubelet 自身、控制平面组件 |
| TCP  | 入站 | 30000-32767 | NodePort 服务† | 所有组件                   |

### 容器运行时

参考 [清华大学开源软件镜像站 Docker Community Edition 镜像使用帮助](https://mirrors.tuna.tsinghua.edu.cn/help/docker-ce/)。

### 安装kubeadm

先信任软件仓库的证书，要注意的是证书托管在谷歌，所以基本不用考虑直接执行命令能成功了。

```shell
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
```

作为代替，可以先手动魔法上网下载到证书，再变通一下完成证书添加。

```shell
cat apt-key.gpg | sudo apt-key add -
```

之后添加源，源的版本并不能直接对应到发行版的版本，目前 ubuntu server 只支持到 16.04 LTS ，或者 Debian 9 Stretch 。更高版本也可以装，但我比较怀疑官方的包到底有没有在新发行版里测试过，支持力度行不行。

总之，如果宿主机不拿来当开发环境使的话，上个 Ubuntu server 16.04 LTS 也没事，只要还没有完全停止支持就好。总之这个问题上我保留意见吧。

```shell
echo 'deb https://mirrors.tuna.tsinghua.edu.cn/kubernetes/apt kubernetes-xenial main' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

添加软件源之后更新软件包清单并安装 `kubelet`、`kubeadm`、`kubectl` 。

```shell
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

### 检查

首先确认所有 `kubelet`、`kubeadm`、`kubectl` 命令都已经可用，如果命令不存在则说明安装有问题，根据具体情况处理。

然后检查`kubelet`服务的状态（注意用了`systemd`，不确定有没有用 `upstart` 或别的 Unix 风格的服务管理的）。

运行命令 `sudo systemctl status kubelet` 得到下面的输出。

```plaintext
● kubelet.service - kubelet: The Kubernetes Node Agent
     Loaded: loaded (/lib/systemd/system/kubelet.service; enabled; vendor preset: enabled)
    Drop-In: /etc/systemd/system/kubelet.service.d
             └─10-kubeadm.conf
     Active: activating (auto-restart) (Result: exit-code) since Fri 2021-11-19 02:32:29 UTC; 9s ago
       Docs: https://kubernetes.io/docs/home/
    Process: 6767 ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS (code=exited, status=1/FAILURE)
   Main PID: 6767 (code=exited, status=1/FAILURE)
```

此时的 `kubelet` 服务还是失败的状态，再检查 `kubelet` 的日志，通过 `sudo journalctl -u kubelet` 。

```plaintext
-- Logs begin at Thu 2021-11-18 07:40:58 UTC, end at Fri 2021-11-19 02:34:19 UTC. --
Nov 19 02:27:41 vm systemd[1]: Started kubelet: The Kubernetes Node Agent.
Nov 19 02:27:42 vm systemd[1]: kubelet.service: Current command vanished from the unit file, execution of the command list won't be resumed.
Nov 19 02:27:42 vm systemd[1]: Stopping kubelet: The Kubernetes Node Agent...
Nov 19 02:27:42 vm systemd[1]: kubelet.service: Succeeded.
Nov 19 02:27:42 vm systemd[1]: Stopped kubelet: The Kubernetes Node Agent.
Nov 19 02:27:42 vm systemd[1]: Started kubelet: The Kubernetes Node Agent.
Nov 19 02:27:42 vm kubelet[5944]: E1119 02:27:42.559949    5944 server.go:206] "Failed to load kubelet config file" err="failed to load Kubelet config file /var/lib/kubelet/config.yaml, error failed to read kube>
Nov 19 02:27:42 vm systemd[1]: kubelet.service: Main process exited, code=exited, status=1/FAILURE
Nov 19 02:27:42 vm systemd[1]: kubelet.service: Failed with result 'exit-code'.
Nov 19 02:27:52 vm systemd[1]: kubelet.service: Scheduled restart job, restart counter is at 1.
Nov 19 02:27:52 vm systemd[1]: Stopped kubelet: The Kubernetes Node Agent.
Nov 19 02:27:52 vm systemd[1]: Started kubelet: The Kubernetes Node Agent.
Nov 19 02:27:52 vm kubelet[6119]: E1119 02:27:52.804723    6119 server.go:206] "Failed to load kubelet config file" err="failed to load Kubelet config file /var/lib/kubelet/config.yaml, error failed to read kube>
Nov 19 02:27:52 vm systemd[1]: kubelet.service: Main process exited, code=exited, status=1/FAILURE
Nov 19 02:27:52 vm systemd[1]: kubelet.service: Failed with result 'exit-code'.
```

失败的原因是 `Failed to load kubelet config file" err="failed to load Kubelet config file /var/lib/kubelet/config.yaml, error failed to read kube>`。

## 创建集群

目标是创建一个单节点的集群。

### 拉取镜像

众所周知的原因，`kubernetes` 的镜像托管在谷歌服务器上，麻瓜是访问不到的，所以就连拉取镜像也值得用几十个字来说。

```shell
sudo kubeadm config images pull --image-repository registry.cn-hangzhou.aliyuncs.com/google_containers
```

### 初始化主节点

注意使用 `kubeadm config images pull` 拉取了镜像的话，在 `init` 阶段除非你把镜像 tag 给改了，不然也要传个 `--image-repository` 参数。

```shell
sudo kubeadm init --image-repository registry.cn-hangzhou.aliyuncs.com/google_containers
```

完整输出如下。

```plaintext
[init] Using Kubernetes version: v1.22.4
[preflight] Running pre-flight checks
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action in beforehand using 'kubeadm config images pull'
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "ca" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local vm] and IPs [10.96.0.1 10.0.2.15]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-ca" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Generating "etcd/ca" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [localhost vm] and IPs [10.0.2.15 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [localhost vm] and IPs [10.0.2.15 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests". This can take up to 4m0s
sudo kubeadm init --image-repository registry.cn-hangzhou.aliyuncs.com/google_containers[apiclient] All control plane components are healthy after 9.003038 seconds
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config-1.22" in namespace kube-system with the configuration for the kubelets in the cluster
[upload-certs] Skipping phase. Please see --upload-certs
[mark-control-plane] Marking the node vm as control-plane by adding the labels: [node-role.kubernetes.io/master(deprecated) node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[mark-control-plane] Marking the node vm as control-plane by adding the taints [node-role.kubernetes.io/master:NoSchedule]
[bootstrap-token] Using token: jfhacg.2ahc3yqndiwct9vk
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.0.2.15:6443 --token jfhacg.2ahc3yqndiwct9vk \
        --discovery-token-ca-cert-hash sha256:377d6ead2bde8373000333d883c9bd9449233686fe277814ccade0b55fc362a1
```

因为是虚拟机里的集群，也没打算给任何人访问，关键信息懒得打码了。

几个值得关注的内容：

```shell
# Your Kubernetes control-plane has initialized successfully!

# To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf
```

首先，集群控制平面已经初始化成功了，说明命令执行基本 OK，没有致命错误。

后面就是教你怎么配置 `kubectl` 来访问控制平面，集群的管理员配置放在 `/etc/kubernetes/admin.conf` ，可以用 `KUBECONFIG` 环境变量来使用，或者把配置文件复制到家目录下的路径 `~/.kube/config` 。

```plaintext
You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/
```

提示你应该部署一个 POD 网络到集群，也就是一般说的 CNI 插件，以便 POD 之间可以互相通信。安装插件之前，集群的 DNS （`CoreDNS`） 不会启动。

```plaintext
Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.0.2.15:6443 --token jfhacg.2ahc3yqndiwct9vk \
        --discovery-token-ca-cert-hash sha256:377d6ead2bde8373000333d883c9bd9449233686fe277814ccade0b55fc362a1
```

一旦搞定了网络插件，就可以用 `kubeadm` 继续添加新的节点到集群里了。

### 安装网络插件

看起来大家都在用 `calico` 做 POD 网络，所以我也用 `calico` 好了。步骤参考 `calico` 的[官方文档](https://docs.projectcalico.org/getting-started/kubernetes/self-managed-onprem/onpremises) 和 [官方的快速开始](https://docs.projectcalico.org/getting-started/kubernetes/quickstart) 来配置一个单节点集群的 POD 。

正式开始前，参考上面的内容配置好 `kubectl` ，以便无需 root 权限运行 `kubectl` 命令。

先下载 `calico` 的 k8s 资源。

```shell
curl https://docs.projectcalico.org/manifests/calico-typha.yaml -o calico.yaml
```

按照说明，判断下 POD 的 CIDR（POD的网段），用 `sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get cm kubeadm-config -n kube-system -o yaml` 获取 `kubeadm-config` 这个 `configmap`，检查其中的 `networking.podSubnet` 值。在我这里的输出如下。

```yaml
apiVersion: v1
data:
  ClusterConfiguration: |
    apiServer:
      extraArgs:
        authorization-mode: Node,RBAC
      timeoutForControlPlane: 4m0s
    apiVersion: kubeadm.k8s.io/v1beta3
    certificatesDir: /etc/kubernetes/pki
    clusterName: kubernetes
    controllerManager: {}
    dns: {}
    etcd:
      local:
        dataDir: /var/lib/etcd
    imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers
    kind: ClusterConfiguration
    kubernetesVersion: v1.22.4
    networking:
      dnsDomain: cluster.local
      serviceSubnet: 10.96.0.0/12
    scheduler: {}
kind: ConfigMap
metadata:
  creationTimestamp: "2021-11-19T02:54:04Z"
  name: kubeadm-config
  namespace: kube-system
  resourceVersion: "210"
  uid: 2567d366-2257-4114-8709-12b016cd1fe8
```

可以发现没有 `podSubnet`，那就当是默认，按照 `calico` 文档说明不用改 `yaml`，正常应用。

```shell
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f calico.yaml
```

输出如下。

```plaintext
configmap/calico-config created
customresourcedefinition.apiextensions.k8s.io/bgpconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/bgppeers.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/blockaffinities.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/caliconodestatuses.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/clusterinformations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/felixconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworksets.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/hostendpoints.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamblocks.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamconfigs.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamhandles.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ippools.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipreservations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/kubecontrollersconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networksets.crd.projectcalico.org created
clusterrole.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrolebinding.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrole.rbac.authorization.k8s.io/calico-node created
clusterrolebinding.rbac.authorization.k8s.io/calico-node created
service/calico-typha created
deployment.apps/calico-typha created
Warning: policy/v1beta1 PodDisruptionBudget is deprecated in v1.21+, unavailable in v1.25+; use policy/v1 PodDisruptionBudget
poddisruptionbudget.policy/calico-typha created
daemonset.apps/calico-node created
serviceaccount/calico-node created
deployment.apps/calico-kube-controllers created
serviceaccount/calico-kube-controllers created
poddisruptionbudget.policy/calico-kube-controllers created
```

出现了一个弃用警告，无视之，反正是 `calico` 的问题。再检查下相关的 `POD` 创建是否成功，用命令 `kubectl get pod -n kube-system`，输出如下。

```plaintext
NAMESPACE     NAME                                       READY   STATUS    RESTARTS      AGE
kube-system   calico-kube-controllers-5d995d45d6-gwwrw   1/1     Running   0             5m29s
kube-system   calico-node-sgb2x                          0/1     Running   2 (49s ago)   5m29s
kube-system   calico-typha-7df55cc78b-hpfkx              0/1     Pending   0             5m29s
kube-system   coredns-7d89d9b6b8-c7sxl                   1/1     Running   0             32m
kube-system   coredns-7d89d9b6b8-tjsj8                   1/1     Running   0             32m
kube-system   etcd-vm                                    1/1     Running   0             32m
kube-system   kube-apiserver-vm                          1/1     Running   0             32m
kube-system   kube-controller-manager-vm                 1/1     Running   0             32m
kube-system   kube-proxy-d64kh                           1/1     Running   0             32m
kube-system   kube-scheduler-vm                          1/1     Running   0             32m
```

可以看到至少镜像是拉到了。

`calico-typha-7df55cc78b-hpfkx` 这个 POD 的 `describe` 显示不能运行在 `master` 节点。

```plaintext
Events:
  Type     Reason            Age                  From               Message
  ----     ------            ----                 ----               -------
  Warning  FailedScheduling  56s (x9 over 8m57s)  default-scheduler  0/1 nodes are available: 1 node(s) had taint {node-role.kubernetes.io/master: }, that the pod didn't tolerate.
```

而 `calico-node-sgb2x` 的日志显示需要 `calico-typha` 才能运行。

```plaintext
2021-11-19 03:27:46.413 [ERROR][1674] confd/discovery.go 153: Didn't find any ready Typha instances.
2021-11-19 03:27:46.413 [FATAL][1674] confd/startsyncerclient.go 48: Typha discovery enabled but discovery failed. error=Kubernetes service missing IP or port
bird: Unable to open configuration file /etc/calico/confd/config/bird6.cfg: No such file or directory
```

因为想要的是一个单节点集群，所以接下来把本节点的污点 `node-role.kubernetes.io/master-` 给去掉。

```shell
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf taint nodes --all node-role.kubernetes.io/master-
```

输出

```plaintext
node/vm untainted
```

再观察 `kube-system` 里的 POD 状态。

```plaintext
NAME                                       READY   STATUS    RESTARTS      AGE
calico-kube-controllers-5d995d45d6-gwwrw   1/1     Running   0             11m
calico-node-sgb2x                          1/1     Running   7 (38s ago)   11m
calico-typha-7df55cc78b-hpfkx              1/1     Running   0             11m
coredns-7d89d9b6b8-c7sxl                   1/1     Running   0             38m
coredns-7d89d9b6b8-tjsj8                   1/1     Running   0             38m
etcd-vm                                    1/1     Running   0             38m
kube-apiserver-vm                          1/1     Running   0             38m
kube-controller-manager-vm                 1/1     Running   0             38m
kube-proxy-d64kh                           1/1     Running   0             38m
kube-scheduler-vm                          1/1     Running   0             38m
```

可以看到所有的POD都已经进入`Ready`状态。

最后通过 `kubectl get nodes -o wide` 检查节点状态。

```plaintext
NAME   STATUS   ROLES                  AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
vm     Ready    control-plane,master   39m   v1.22.4   10.0.2.15     <none>        Ubuntu 20.04.3 LTS   5.4.0-90-generic   docker://20.10.11
```

到这里单节点集群就成功部署了。

## 总结

之后还可以部署 dashboard 之类的应用验证，不想写了，浪费时间。

写了一大堆又删掉了。

如果一定要总结的话，k8s，学了进小厂吧，小厂不用；学了进大厂吧，大厂也不要你。

