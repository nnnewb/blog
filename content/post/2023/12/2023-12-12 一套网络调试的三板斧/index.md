---
title: 一套Linux网络开发/调试/运维的三板斧
date: 2023-12-12 19:08:56
image: cover.jpg
categories:
- linux
tags:
- linux
- go
- network
---

## 前言

作为网络领域的一个菜鸡，谈不了什么深入的东西。

近两年的工作里接触比较多的，容器编排工具如k8s、compose，虚拟机编排工具如 libvirt、openstack、ESXi 这些玩意儿，多少都有网络层的虚拟化和编排能力。而我负责做蜜罐系统的主机防火墙策略、蜜罐网络编排、流量牵引，不可避免就会碰到很多网络问题。

本文不能算正经技术分享文，就当成我对着空气和幻想中的朋友闲聊吧。梳理下从入职到离职这一年多以来，积累的一些技术实践，为建立知识体系做准备，先把点连成线。

## 三板斧之 tcpdump/wireshark

`tcpdump` 是最管用的一板斧，跟电工手里的万用表一样。调试防火墙策略、网络转发的时候，常见的异常表现就是没收到/没发出/连接异常，这些都可以通过 `tcpdump` 排查。

比如某个 `docker-compose` 编排的业务服务容器，暴露方式是 `docker-compose.yaml` 的 `ports` 配置，自定义 docker 网络。问题表现是浏览器访问超时，反向代理没有 access log。主机没有开启 firewalld/ufw，selinux 已关闭，有自定义防火墙加固策略。那么问题的阻塞点在哪儿？

`tcpdump` 这时候就跟万用表一样出场了。先看看物理网卡的链路收到流量了没？`tcpdump -i eno3 tcp and port 443 -nn`，哦吼，根本没收到。所以问题不在  我们服务器上，直接推给客户网管排查。

再例如，改了个 `libvirtd` 的配置后重启了一下 `libvirtd`，发现虚拟机全部不联网了，虚拟机硬件配置无异常。怎么办？`tcpdump` 看下网桥流量，咦，没有。再看下桥接，哦，虚拟机 tap 网卡 `vnet*` 怎么全都断开桥接了？重新 `brctl addif br-test vnet1` 接上，问题解决。再看是否是改配置重启 `libvirtd` 的影响，加上对应处理。

`tcpdump` 和 `wireshark` 结合使用效果更好，主要是 `tcpdump` 分析流量内容没 `wireshark` 简单直观。前公司的流量牵引功能实现里，有个用 go 写的的低效软件 NAT 和 tun 网卡，调试过程就会需要看 TCP 报头的字段在转发过程里变化，偶尔也需要看报文内容。`tcpdump` 抓好的包还是用 `wireshark` 分析更方便。

## 三板斧之 iptables

以我有限的经验来看，Linux 网络防火墙基本都包含一定程度上对 iptables 的接管。不论是 `firewalld` 还是 `ufw`，乃至国产麒麟桌面版自带的防火墙。麒麟桌面有两套防火墙，`ufw` 和一套没有提供 cli 的防火墙 `kylin-firewall`，就是配置在 `/etc/kylin-firewall` 里的那套玩意儿。服务器版则只有 `firewalld`。桌面版和服务器版来源大概一个是ubuntu一个是centos。

`iptables` 作为 Linux 防火墙技术的事实标准是必学的。工作常用的 `docker` 也好，`libvirt` 也好，默认都会涉及一些 `iptables` 控制。

`iptables` 最让人烦的就是如果有多个程序想搞 iptables 策略，程序本身写得还不太好的时候，很容易导致策略顺序错乱。而 `iptables` 策略对顺序又是敏感的。像 `docker` 一样建一条用户策略链是个很好的选择，程序只需要确保用户链策略的存在性和相对顺序，内置链的跳转策略只需要要求存在。但 `libvirt` 有点粗暴，策略直接写内建链里，相对就容易出毛病。

在前司工作的时候，设计防火墙策略时就考虑了大家伙儿一起操作 `iptables` 对策略顺序的影响，而且软件化、云部署等客户已有环境上部署的复杂场景，要求接管 `iptables` 不太现实。所以仅做了一些有限的控制。比如，要求 `docker-compose.yaml` 不配置 `ports` 端口映射，因为 `docker-proxy` 常出毛病。`docker` 不接管 `iptables`，业务容器 IP 采用静态定义+`iptables`主动控制端口映射。`libvirtd`也是，网络策略尽可能选择了自行接管，降低协作的复杂度。而这个决策的 tradeoff ，评估认为让 `docker` + `libvirtd` + 我们的管理服务 + 防火墙 协作管理 `iptables` 的成本收益比太低。

接管 `docker` 和 `libvirtd` 的策略还算好推，至于宿主机的防火墙，由于确实有客户在乎这个点（可能是内审合规要求？），所以接管后的策略还是以用户链的形式配置的。客户如果想保留防火墙协同管理 `iptables` 策略，也可以，客户自行配置下防火墙的策略就好啦。

另外几个 `iptables` 的坑值得一提。

一个是 `iptables` 的 `LOG` 目标和 `TRACE` 目标打不出日志，`dmesg` 啥也看不到。可能是没加载 `nf_log_ipv4` 模块。`modprobe nf_log_ipv4` 加载下就行。

还有 `iptables` 的内置表、链或目标不存在，比如 `iptables -t nat -S` 提示没有 `nat` 表，原因可能是 `iptables` 安装损坏了，内核模块丢失。可以尝试重装。需要注意 `iptables` 的内核模块包含在哪个包里。而目标不存在则考虑下是不是 `iptables` 版本太低了。SLES 11 SP4 这个老古董发行版就缺很多目标。

## 三板斧之 iproute2

`iproute2` 是一套网络工具，是 `ifconfig`、`brctl`、`netstat`、`route` 这套 `net-tools` 工具的替代。现在 `ifconfig` 这套命令行工具是弃用状态，很多发行版较新版本要么不带 `net-tools` 要么就是 `net-tools` 和 `iproute2` 共存了。

`iproute2` 这个包最主要用的工具还是 `ip` ，用来调链路属性（UP/DOWN等）、IP地址、路由表和策略路由、ARP、隧道等。还有大伙儿应该听过的 `ss` ，`netstat` 的替代，以及个人用的比较少的 `bridge` 。

`iproute2` 这套工具都是基于 `netlink` 协议和内核通信的，用 go 写网络代码应该对 `github.com/vishvananda/netlink` 这个包不陌生，很多 `iproute2` 的功能可以在这个包里找到对应的 API 。

## 内核参数

常用的内核参数列一下。

`net.ipv4.ip_forward` ，控制是否允许跨网卡的IP报文转发，或者简单点说就是路由功能。修改这个配置会影响其他配置，所以还是用 `net.ipv4.conf.all.forwarding` 更好。`net.ipv6.conf.all.forwarding` 是对应参数的 IPv6 版本。

`net.ipv4.conf.all.rp_filter`，如果反向路由校验不通过则丢弃包，也是在多网卡环境下有影响。举例来说，网卡 eno4 配置的 IP 是 `172.19.0.1/24`，但 eno4 收到了来自 `192.168.1.100` 的报文，系统没有针对这个 IP 的路由，而且 eno4 没有默认路由，返程会走另一个网卡。这种情况下就会丢弃报文而不处理。

## NetworkManager 和其他

一些经验技巧性的东西。

现在常见的 RHEL 系发行版和基于 RHEL 系发行版衍生的“兼容”、“自主”发行版基本都用的 `NetworkManager`，坚持不把 `NetworkManager` 设为默认的，主流发行版里除了 Arch Linux 这样让你自己选的之外，应该就剩 Debian 了。其他更小众的不谈。至于商用的，SLES、RHEL 都是默认 `NetworkManager` 。学会用 `NetworkManager` 还是很有必要的。

`NetworkManager` 的主要命令行交互界面是 `nmcli` 命令，具体翻文档。给网络配置功能做图形前端主要用 `NetworkManager` 的 D-Bus 接口。D-Bus 是个非常恶心的玩意儿，但目前没有其他替代，主流 Linux 服务适配的还是它。特别是 systemd 那套东西。有个已知的情况是在 systemd 系统上配 sys-v 启动脚本，有概率在 journald 采集到 systemd 启动的 sys-v 服务相关的 D-Bus 错误 （忘记具体错误消息是啥了，队列满什么的吧。）。安全行业客户日志审计遇到 error 都要我们给个解释，很难顶。专门去学 D-Bus 又很傻逼，ROI 太低。

还有专门提一嘴的，APUE 这书真的值得手边参考。很多 *nix 常见编程范式都囊括了。读没读过这书做出来的程序设计真的会很不一样。

## 总结

后面再想想归纳下这两年的工作经历，项目经验和教训。
