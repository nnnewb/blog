---
title: 我的 Ubuntu Server 虚拟机配置
date: 2022-12-31 17:15:43
categories:
- linux运维
tags:
- linux运维
- ubuntu
---

Ubuntu Server 是我目前比较习惯用的开发用 Linux 虚拟机系统，选择 Ubuntu Server 的原因也很简单：问答资源什么的比较丰富，安装过程足够快捷可控，以及日常开发使用中相对没那么折腾。

但 Ubuntu Server 默认配置也有些比较恶心人的东西，比如那个 `snapd` ，平时基本用不到，但系统用了一段时间后经常看到 `snapd` 关机的时候等待 120s 或者启动报错之类。同样比较烦人的是 `systemd-networkd-wait-online` ，会拖慢开机时间，而且经常能看到失败。

且不说这个检查机制到底是怎么实现的，虚拟机环境基本不配什么开机启动依赖网络的服务，等网络确实没什么意义。

最后还有一个比较迷惑的问题，默认装完 Ubuntu Server 设置的 systemd target 是 graphical ，但安装选项是不含桌面的。所以为了不加载没啥用还可能导致问题的服务，默认 target 也得改成 multi-user 。

具体流程：

```shell
# 卸载和禁用 snapd
sudo apt autoremove --purge snapd
sudo apt-mark hold snapd

# 修改 systemd-networkd-wait-online 的等待时间
# ExecStart=/lib/systemd/systemd-networkd-wait-online --timeout 1
# 加上 --timeout 1
sudo systemctl edit systemd-networkd-wait-online.service --full

# 修改目标 multi-user
sudo systemctl set-default multi-user

# 重启生效
sudo reboot
```

这是一方面。

另外还有个比较讨厌的问题是网络配置，公司内网不允许虚拟机桥接，而 NAT 模式宿主机是不能直接通过 IP 访问虚拟机的，所以还得加一张 Host-Only 网卡。此外，因为工作需要，还得准备两台用来给公司代码编译打包的虚拟机（也是历史遗留的大坑），以及一台测试用的虚拟机。这些虚拟机之间需要互通，然而 NAT 模式网卡也是不支持虚拟机之间互通的，所以还是要加 Host-Only 网卡。

然后就是 Host-Only 网卡的问题了，默认是 DHCP 分配 IP ，会偶发的出现虚拟机 IP 改变，导致一些写好的脚本不得不改下才能跑。所以还得顺便改下静态 IP 。嗯，虚拟机有部分是 CentOS 的，配置静态 IP 方法和 Ubuntu Server 不一样，但这篇只聊下 Ubuntu Server 的配置静态 IP 方法。

简而言之，参考 [Canonical Netplan](https://netplan.io/examples) 这篇文档。在 `/etc/netplan/` 下面新建一个 `01-host-only.yaml` 配置如下。

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens37:
      dhcp4: no
      addresses: [192.168.129.101/24]
      nameservers:
        addresses: [114.114.114.114,114.114.115.115]
      routes:
        - to: 192.168.129.0/24
          via: 192.168.129.1
```

需要注意的是得看下虚拟机的 Host-Only 网卡配置的是哪个网段，以及 Host-Only 的网卡名是什么（我的机器上是 `ens37`）。Host-Only 网卡配 `nameservers` 没啥意义我这写了也就写了。

改好之后 `sudo netplan aplpy` 应用，再试试 `ip addr show` 看看生效了，`ping -I ens37 192.168.129.xxx` 试下能不能通其他 Host-Only 网卡的 IP 。最好再试下 `curl -L https://www.baidu.com/` 看看正常上网有没有问题。