---
title: 运维瞎记 2021年11月11日
description: 瞎运维的操作笔记，但愿别让我有机会去生产环境里瞎折腾
slug: blind-op-2021-11-11
date: 2021-11-11 10:19:00
image: cover.png
categories:
- linux运维
tags:
- linux运维
---

## 记虚拟机网络未连接

### 起因

因为Ubuntu server安装时更新的话需要从网络下载，慢的一批，所以安装的时候虚拟机的网络断开了，安装好启动之后才重新链接。

但是...

连接后进入系统却发现并没有网络（VirtualBox），检查 `networkctl` 发现 `enp0s3` 是 `off` 状态。

### 原因

别问，不知道。

### 处理

顺藤摸瓜不求甚解了。

看到 `enp0s3` 是 `off` 那就先查查怎么解决。

```shell
sudo ip link set enp0s3 up
```

再检查连接状态。

```shell
networkctl status
```

发现连接进入 `downgrade` 状态，搜索得知是未分配 IP 地址。

```shell
sudo dhclient enp0s3
```

报了一个奇怪的CMP什么的错误，不管了。再检查下网络。

```shell
networkctl
```

发现 `enp0s3` 进入 `routable` 状态，大功告成。

### 总结

我总结个蛋。

> 2022年5月6日 补充
>
> 发现问题本源是 netplan 配置未正确生成，dhclient 是暂时性解决。彻底解决的办法是在 `/etc/netplan` 添加 `01-netcfg.yaml`，内容如下：
>
> ```yaml
> network:
> 	version: 2
> 	renderer: networkd
> 	ethernets:
> 		enp0s3:
> 			dhcp4: true
> ```
>
> 注意 `enp0s3` 改成你自己的以太网连接名，用 `networkctl` 或者 `ip show addr` 都能列出来。
>
> 文件添加好之后用命令：
>
> ```bash
> sudo netplan generate
> sudo netplan apply
> ```
>
> 就好了。之后重启vm再运行
>
> ```bash
> networkctl
> ```
>
> 可以看到
>
> ```plaintext
> IDX LINK            TYPE     OPERATIONAL SETUP
>   1 lo              loopback carrier     unmanaged
>   2 enp0s3          ether    routable    configured
>   3 docker0         bridge   no-carrier  unmanaged
>   4 br-e2b0cf462af2 bridge   no-carrier  unmanaged
> 
> 4 links listed.
> ```
>
> 注意 `enp0s3` 已经变成了 `configured` 状态，确认问题彻底处理完毕。
