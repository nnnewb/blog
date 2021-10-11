---
title: k3s更新客户端证书的偷懒方法
slug: k3s-renew-client-ca-file-the-lazy-way
date: 2021-10-11 13:58:00
categories:
- kubernetes
tags:
- kubernetes
- devops
---

## 前言

今天上内网服务器看了眼，准备调试下新代码，结果发现报错 `You must logged in to the server (unauthorized)` 。翻了半天的 *KUBECONFIG* 配置，发现啥也没错。换成 `/etc/rancher/k3s/k3s.yaml` 也不行。于是查了下 `journalctl -r -u k3s` ，发现日志 `x509: certificate has expired or not yet valid: current time ...` ，这就明确了是证书过期了。

于是又找了一圈如何给k3s更新证书，搜 `how to renew client-ca-file` 查出来的方法不是 `kubeadm` 就是改时间、换证书，总之...麻烦，而且搜出来的文章可操作性都有点差，真要实践出真知也不能放公司的机器上，搞出点问题还得劝自己心平气和磨上一整天去解决。

于是终于找到个看起来能行的办法：重启。

## 操作

这个办法可操作性很强——反正情况不会变得更差了。因为办公室的服务器并不能保证24小时不断电，有时候白天上班机器是关机的，重启k3s无论如何不会导致问题变得更差——就算放着不管，过两天说不定也会断电重启下。

确认没人用服务之后直接上手。

```shell
sudo systemctl restart k3s
```

等待重启完成，测试下新的 `k3s.yaml` 能不能正常用。

```shell
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl cluster-info
```

```
Kubernetes control plane is running at https://192.168.2.175:6443
CoreDNS is running at https://192.168.2.175:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://192.168.2.175:6443/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

其他 `get nodes` 之类的命令也顺利完成，剩下就是把新的客户端证书合并到个人的配置里了（对，并不是直接用 `/etc/rancher/k3s/k3s.yaml`，我知道有人会这么用）。办法也简单，`vim /etc/rancher/k3s/k3s.yaml`，把里面的 `users` 键下，`default` 用户的信息复制出来，粘贴到个人的 `~/.kube/config` 相应位置就好。以前复制过的话，就覆盖掉。

## 总结

没啥好总结的，重启大法解决一切问题。不过手动轮换证书的办法也得记录一下，这里留相关的摘要链接。

- [kubernetes.io/使用 kubeadm 进行证书管理](https://kubernetes.io/zh/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)
- [ibm.com/renewing kubernetes cluster certificates](https://www.ibm.com/docs/en/fci/1.1.0?topic=kubernetes-renewing-cluster-certificates)
- [forum.rancher.com/how to renew cert manually?](https://forums.rancher.com/t/how-to-renew-cert-manually/20022)

比较好奇的有多个master节点的集群，能通过逐个重启master节点来实现自动更新证书吗？

