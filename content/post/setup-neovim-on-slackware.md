---
title: 在 slackware 上安装 neovim
date: 2021-01-04 15:00:20
categories:
  - linux运维
tags:
  - slackware
  - vim
  - neovim
references:
  - title: sqg - sbopkg queue generator
    url: https://sbopkg.org/queues.php
  - title: Transitioning from Vim
    url: https://neovim.io/doc/user/nvim.html#nvim-from-vim
---

最近在虚拟机里折腾 slackware ，发现 slackware 14.2 的 vim 版本还停留在 7.4 ，于是考虑还是装个 neovim 算了。毕竟升级 vim8 还得自己写 SlackBuild，万一和原本的 vim 7.4 冲突就更头疼了。

<!-- more -->

## 0x01 确定依赖

到处翻 slackbuild 之间依赖关系的时候发现 sbopkg 提供了一个解决依赖的脚本，`sqg`。

于是简单点，拿 `sqg -p neovim` 生成 neovim 的安装队列 neovim.sqf 文件。

sqg 和 sbopkg 一起提供了，所以不用另外安装。

## 0x02 安装

一条命令：`sudo sbopkg -i neovim.sqf`

然后等完成吧。

## 0x03 可选依赖

上述步骤完成后还只是装好基本的 neovim ，但 python2/python3/ruby/nodejs 支持都是没有的。

打开 nvim，输入命令 `:checkhealth` 后会显示缺少支持，同时也提供了解决办法：`pip install pynvim`。

然后就是另一个坑：pip 也不在默认的 python2 包里。于是为了解决这个问题，还得先装上 pip : `sudo sbopkg -i python-pip`

然后执行 `sudo pip install pynvim`，此时 python2 支持已经装好。

不过众所周知 python2 的生命周期已经结束了，python3 才是正道。所以还得装一下 python3 : `sudo sbopkg -i python3`

slackbuild 的 python3 包自带了 pip 所以一切安好。完成后直接装 pynvim 即可: `sudo pip3 install pynvim`

nodejs 和 ruby 不是我的工作语言就不管了。

## 0x04 使用 vim 配置

另一个问题是我的 vimrc 配置是针对 vim8 写的，neovim 不认 .vimrc 和 .vim 。这个问题网上有很多解决办法，我复制粘贴下。

> Transitioning from Vim _nvim-from-vim_
>
> 1. To start the transition, create your |init.vim| (user config) file:
>
>    :call mkdir(stdpath('config'), 'p')
>    :exe 'edit '.stdpath('config').'/init.vim'
>
> 2. Add these contents to the file:
>
>    set runtimepath^=~/.vim runtimepath+=~/.vim/after
>    let &packpath = &runtimepath
>    source ~/.vimrc
>
> 3. Restart Nvim, your existing Vim config will be loaded.

完事即可认出 vim 配置。

## 0x05 Happy Hacking !

_完_
