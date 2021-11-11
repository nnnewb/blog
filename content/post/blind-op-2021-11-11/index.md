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

