---
title: git魔法上网的技巧
slug: git-magic-surfing-skill
date: 2022-06-23 17:50:00
categories:
- git
tags:
- git
---

## 前言

不想再在配置新虚拟机之类的环境的时候临时现查了。

## ssh 方式

简而言之，利用 `.ssh/config` 配置一条 `ProxyCommand` 即可，linux 下考虑用 `nc`，windows 非 git bash 可以装个 nmap 用里面带的 `ncat` 工具，git bash 下可以用 `connect` 。

### Linux 下用 nc 命令

```
Host github.com
    HostName github.com
    ProxyCommand nc -X 5 -x 127.0.0.1:7891 %h %p
    Port 22
    User git
    PubKeyAuthentication yes
```

特别注意 `-X 5` 表示魔法类型是 s0cks5 ，Windows 下 C 开头的软件在一个端口同时支持了 http 魔法和 s0cks 魔法所以可以直接配同一个端口，Linux 下 C 开头软件社区版是分开监听的，所以别写错了。

### Windows 非 Git Bash 下用 ncat 命令

```
Host github.com
    HostName github.com
    Port 22
    User git
    ProxyCommand C:/Users/USER/scoop/shims/ncat.exencat --proxy 127.0.0.1:7890 %h %p
```

特别注意路径，`ncat`使用完整路径，而且不要用反斜杠，用正斜杠。

### Windows Git Bash 下可以用 connect 命令

```
Host github.com
    HostName github.com
    Port 22
    User git
    ProxyCommand connect -S 127.0.0.1:7890 %h %p
```

没用过，不知道有什么坑。

## https 方式

在 `~/.gitconfig` 里这样配置。

```
[http "https://github.com"]
    proxy = socks5://192.168.10.120:7890
```

魔法类型和端口注意改成自己的。

## 总结

如果不是工作需要，麻瓜大可用 gitee 一类的服务，反正免费私有仓库对个人把玩用途绝对够了。

Pages 的话最好走正规渠道。
