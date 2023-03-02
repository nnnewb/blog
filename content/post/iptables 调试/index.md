---
title: iptables 调试方法
date: 2023-03-02 17:36:09
categories:
- linux运维
tags:
- linux运维
- iptables
---

工作忙长话短说，写的匆忙，参考文章见文末。

## 应对场景

因为工作面对的网络环境有点复杂，业务需要做了基于 Tun 网卡的隧道转发流量，然后流量会经过实体机-虚拟机（隧道网关）-虚拟机（蜜罐网络网关）-虚拟机/docker容器一长串转发，基本靠 `ip rule`/`ip route` 还有 `iptables` 制定流量转发规则。

后来简化了整个流量路径，直接从实体机转蜜罐网络。最近就遇到一个 `tcpdump` 抓到了隧道网卡流量，但没有进入 docker 创建的网桥的问题。虽然后来是靠重启了一下隧道服务端解决（问题根源没找到），但中间看另一个同事调规则还是直接 `-j accept` 然后 `iptables -t nat -nvL` 看流量，于是就想起来之前似乎看到过 netfilter 支持 `-j LOG` 还是啥来着，可以把流量打条日志出来。

不过一个一个链跟过去 `iptables -t xxx -I yyy -j LOG` 加日志再看日志很不方便，于是搜了下，发现可以在 `raw` 表 `PREROUTING` 链增加一条 `-j TRACE` 把入站链路匹配的表链规则都打出来。

## 使用

```bash
# 跟踪入站包
iptables -t raw -I PREROUTING -p tcp -s 192.168.13.3 -d 192.168.13.6 --dport 80 -j TRACE
# 跟踪出站包
iptables -t raw -I OUTPUT -p tcp -s 192.168.13.6 -d 192.168.13.3 --sport 80 -j TRACE
```

因为 TRACE 打的内容很丰富，说白了要是不加约束的话打出来的日志量大到没法看，所以最好加上详细的匹配规则，只抓感兴趣的流量。

比如上面的命令只抓 `192.168.13.6:80` 的出站、入站流量，如果遇到像是 80 不知道转发到哪儿了，可以打出来匹配的表链和规则。

```
[root@localhost ~]# iptables -t raw -nvL
Chain PREROUTING (policy ACCEPT 111 packets, 8843 bytes)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 TRACE      tcp  --  *      *       192.168.13.3         192.168.13.6         tcp dpt:80

Chain OUTPUT (policy ACCEPT 67 packets, 15411 bytes)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 TRACE      tcp  --  *      *       192.168.13.6         192.168.13.3         tcp spt:80

```

现在到 192.168.13.3 尝试请求 192.168.13.6 的 80 端口看看。

```
vm :: ~/repos/huanyun » curl -vkL http://192.168.13.6/
*   Trying 192.168.13.6:80...
^C
```

在 192.168.13.6 上使用命令 `journalctl -xek` 查看内核日志。

```
[root@localhost ~]# journalctl -kxe -n 10 --no-pager
-- Logs begin at Tue 2023-02-28 05:48:43 CST, end at Thu 2023-03-02 13:56:16 CST. --
Mar 02 13:56:16 localhost.localdomain kernel: TRACE: mangle:INPUT:policy:1 IN=enp0s8 OUT= MAC=08:00:27:f1:ac:7a:08:00:27:4e:0e:25:08:00 SRC=192.168.13.3 DST=192.168.13.6 LEN=52 TOS=0x10 PREC=0x00 TTL=64 ID=43341 DF PROTO=TCP SPT=38660 DPT=80 SEQ=548562008 ACK=907923156 WINDOW=502 RES=0x00 ACK URGP=0 OPT (0101080AB2CBAA293337B8FC) UID=48 GID=48 
Mar 02 13:56:16 localhost.localdomain kernel: TRACE: filter:INPUT:policy:1 IN=enp0s8 OUT= MAC=08:00:27:f1:ac:7a:08:00:27:4e:0e:25:08:00 SRC=192.168.13.3 DST=192.168.13.6 LEN=52 TOS=0x10 PREC=0x00 TTL=64 ID=43341 DF PROTO=TCP SPT=38660 DPT=80 SEQ=548562008 ACK=907923156 WINDOW=502 RES=0x00 ACK URGP=0 OPT (0101080AB2CBAA293337B8FC) UID=48 GID=48 
Mar 02 13:56:16 localhost.localdomain kernel: TRACE: raw:PREROUTING:policy:2 IN=enp0s8 OUT= MAC=08:00:27:f1:ac:7a:08:00:27:4e:0e:25:08:00 SRC=192.168.13.3 DST=192.168.13.6 LEN=52 TOS=0x10 PREC=0x00 TTL=64 ID=43342 DF PROTO=TCP SPT=38660 DPT=80 SEQ=548562008 ACK=907923156 WINDOW=502 RES=0x00 ACK FIN URGP=0 OPT (0101080AB2CBAA293337B8FC) 
Mar 02 13:56:16 localhost.localdomain kernel: TRACE: mangle:PREROUTING:policy:1 IN=enp0s8 OUT= MAC=08:00:27:f1:ac:7a:08:00:27:4e:0e:25:08:00 SRC=192.168.13.3 DST=192.168.13.6 LEN=52 TOS=0x10 PREC=0x00 TTL=64 ID=43342 DF PROTO=TCP SPT=38660 DPT=80 SEQ=548562008 ACK=907923156 WINDOW=502 RES=0x00 ACK FIN URGP=0 OPT (0101080AB2CBAA293337B8FC) 
Mar 02 13:56:16 localhost.localdomain kernel: TRACE: mangle:INPUT:policy:1 IN=enp0s8 OUT= MAC=08:00:27:f1:ac:7a:08:00:27:4e:0e:25:08:00 SRC=192.168.13.3 DST=192.168.13.6 LEN=52 TOS=0x10 PREC=0x00 TTL=64 ID=43342 DF PROTO=TCP SPT=38660 DPT=80 SEQ=548562008 ACK=907923156 WINDOW=502 RES=0x00 ACK FIN URGP=0 OPT (0101080AB2CBAA293337B8FC) UID=48 GID=48 
Mar 02 13:56:16 localhost.localdomain kernel: TRACE: filter:INPUT:policy:1 IN=enp0s8 OUT= MAC=08:00:27:f1:ac:7a:08:00:27:4e:0e:25:08:00 SRC=192.168.13.3 DST=192.168.13.6 LEN=52 TOS=0x10 PREC=0x00 TTL=64 ID=43342 DF PROTO=TCP SPT=38660 DPT=80 SEQ=548562008 ACK=907923156 WINDOW=502 RES=0x00 ACK FIN URGP=0 OPT (0101080AB2CBAA293337B8FC) UID=48 GID=48 
Mar 02 13:56:16 localhost.localdomain kernel: TRACE: raw:OUTPUT:policy:2 IN= OUT=enp0s8 SRC=192.168.13.6 DST=192.168.13.3 LEN=52 TOS=0x00 PREC=0x00 TTL=64 ID=41993 DF PROTO=TCP SPT=80 DPT=38660 SEQ=907923156 ACK=548562009 WINDOW=227 RES=0x00 ACK URGP=0 OPT (0101080A3337B8FFB2CBAA29) UID=48 GID=48 
Mar 02 13:56:16 localhost.localdomain kernel: TRACE: mangle:OUTPUT:policy:1 IN= OUT=enp0s8 SRC=192.168.13.6 DST=192.168.13.3 LEN=52 TOS=0x00 PREC=0x00 TTL=64 ID=41993 DF PROTO=TCP SPT=80 DPT=38660 SEQ=907923156 ACK=548562009 WINDOW=227 RES=0x00 ACK URGP=0 OPT (0101080A3337B8FFB2CBAA29) UID=48 GID=48 
Mar 02 13:56:16 localhost.localdomain kernel: TRACE: filter:OUTPUT:policy:1 IN= OUT=enp0s8 SRC=192.168.13.6 DST=192.168.13.3 LEN=52 TOS=0x00 PREC=0x00 TTL=64 ID=41993 DF PROTO=TCP SPT=80 DPT=38660 SEQ=907923156 ACK=548562009 WINDOW=227 RES=0x00 ACK URGP=0 OPT (0101080A3337B8FFB2CBAA29) UID=48 GID=48 
Mar 02 13:56:16 localhost.localdomain kernel: TRACE: mangle:POSTROUTING:policy:1 IN= OUT=enp0s8 SRC=192.168.13.6 DST=192.168.13.3 LEN=52 TOS=0x00 PREC=0x00 TTL=64 ID=41993 DF PROTO=TCP SPT=80 DPT=38660 SEQ=907923156 ACK=548562009 WINDOW=227 RES=0x00 ACK URGP=0 OPT (0101080A3337B8FFB2CBAA29) UID=48 GID=48
```

我多请求了两次所以日志量会多点，不过内容大概就是这样。

日志字段分几个主要部分：匹配的表链（`mangle:POSTROUTING:policy:1`）、进出设备（`IN= OUT=enp0s8`）、接收方以太网地址（`MAC=08:00:27:f1:ac:7a:08:00:27:4e:0e:25:08:00`）、收发IP（`SRC=192.168.13.3 DST=192.168.13.6`）、协议（`PROTO=TCP`）、收发端口（`SPT=38660 DPT=80`）还有 flag（`ACK FIN URGP=0`）

## 总结

就是这样。

`ip rule` 和 `ip route` 把 《TCP/IP 协议详解》读完了再说，Linux 网络实现好几本大部头在我书架上等着我翻，也不知道几年后能看完。