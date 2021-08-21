---
title: slackware 和虚拟机基本配置
date: 2020-12-30 11:11:56
tags:
  - linux
  - slackware
categories:
  - slackware
references:
  - title: slackware - configuration - System init
    url: http://www.slackware.com/config/init.php
  - title: slackware docs - slackpkg
    url: https://docs.slackware.com/slackware:slackpkg
  - title: slackware - configuration - packages
    url: http://www.slackware.com/config/packages.php
  - title: HOWTO writing a slackbuild script
    url: https://slackwiki.com/Writing_A_SlackBuild_Script#Getting_Started
  - title: slackbuilds
    url: https://slackbuilds.org/
  - title: sbopkg
    url: https://github.com/sbopkg/sbopkg
---

slackware 是一个非常有极客味的 Linux 发行版，因为官方维护的包不多，基本靠 slackbuilds 续命。

slackware 的一个特色是包管理系统不处理依赖关系，这一点劝退不少人。

实际上，虽然我不是很赞同 [这个观点](https://docs.slackware.com/start?id=slackware:package_and_dependency_management_shouldn_t_put_you_off_slackware) ，不过并不妨碍 slackware 成为可玩性相对高的 Linux 发行版之一（另外几个可玩性不错的发行版包括 Arch Linux 和 Gentoo）。

这篇博文实际上就是安利下 slackware 并且简要介绍下怎么在虚拟机里搭建个基本环境来体验游玩。

<!-- more -->

## 0x01 安装

安装的参考文档太多了，个人认为主要的难点在分区和引导。毕竟不像其他更流行的发行版的 GUI 安装引导，对 fdisk 和 parted 这些工具不熟悉、对操作系统引导启动的一些基本概念、原理不了解的人很容易犯下错误而不自知。

这里提供一篇之前在贴吧写的 [安装教程](https://tieba.baidu.com/p/4863103375) ，不做赘述了。

## 0x02 桌面

对习惯了装完就有桌面的用户来说，安装完 slackware 之后遇到的第一个问题就是怎么进入桌面——甚至会问怎么登陆。

这里就挂一张 gif 好了。

{% asset_img 01.gif %}

假设没手贱在安装的时候把 x/kde/xfce 之类的软件包组给去掉的话，就不会有什么问题。

如果需要自动进入桌面，需要手动修改 `/etc/inittab` 文件，把默认的 runlevel 修改为 4 。

具体怎么改，看 gif 。

{% asset_img 02.gif %}

## 0x03 slackpkg 包管理

如果用过 ubuntu ，那么下一个问题可能就是 "怎么没有 apt-get 命令？" 或者 "slackware 用什么命令安装软件？"

答案是有好几个相关命令。

- installpkg
- removepkg
- upgradepkg
- makepkg
- explodepkg
- rpm2targz

大部分命令顾名思义，也不需要额外说明。如果说和 apt 或者 pacman 类似的一个统一的包管理器的话，那就是 slackpkg 。

使用 slackpkg 之前，需要手动修改 /etc/slackpkg/mirrors 文件，选择一个网络状况比较好的软件源地址，把行开头的 # 号去掉。

完事之后用命令 `slackpkg update` 更新一下本地索引，就可以正常用了。

常用的命令包括

- slackpkg search
- slackpkg file-search
- slackpkg install
- slackpkg install-new
- slackpkg upgrade
- slackpkg upgrade-all

具体不细说了，看参考链接，或者自己看看 `man slackpkg` 或者 `slackpkg help`

此外还有个不常用的，和安装时的 `setup` 风格比较类似的工具，`pkgtool`。具体可以自己看看命令。

## 0x04 SlackBuilds

用过 Arch Linux 的 AUR 的用户对这种第三方维护的软件包会比较熟悉， SlackBuilds 对这些用户来说就是另一个 AUR 而已。

不同之处在于，SlackBuilds 需要手动下载脚本和源码，然后自己看 README 再运行编译。

当然这不是说 SlackBuilds 没有类似 yaourt 或者 yay 之类的自动工具，你可以试试 sbopkg 。

这里给个简单的例子，用 sbopkg 安装 fbterm 。

{% asset_img 03.gif %}

## 0x05 编写 SlackBuilds

讲道理，slackware 常用的软件太少，基本全靠 slackbuilds 撑场面。如果 SlackBuilds 上也没有呢？

那只能自己写吧。

对于熟悉 bash 脚本的用户来说这不是什么难事。这篇 [HOWTO 文章](https://slackwiki.com/Writing_A_SlackBuild_Script) 很好地说明了怎么写一个 SlackBuilds 脚本。

## 0x06 参与社区

slackware 中文社区太小了，或者说根本不存在。

能聊几句的基本只有贴吧（实际上现在也找不到人了）或者 GitHub 上（slackwarecn 社区也不活跃）。

如果对 slackware 感兴趣，可以玩一玩，写几个常用软件的 SlackBuilds 脚本什么的。

就这样吧。
