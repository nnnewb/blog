---
title: Windows下go拉取http模块
date: 2023-03-21 17:21:39
categories:
- go
tags:
- go
- git
---

## 现象

内网搭建的 gitlab 没有开启 https，只有 http 服务。允许通过 8022 端口 SSH 协议 clone 或者 80 HTTP 协议。

但是 go 默认不支持（不然就没现在这么多壁画了）。

## 方法

### 1. 编辑 ~/.ssh/config

先 `gvim ~/.ssh/config` 打开 ssh 配置，添加一个 gitlab 的 ssh 配置。

```
Host <gitlab的ip>
    HostName <gitlab的ip>
    Port <gitlab的ssh端口>
    User git
    IdentityFile <你的ssh私钥路径>
```

这一步的目的是万一你的端口不是22的话，后续git配置还能读ssh配置选择正确的端口。

### 2. 编辑 ~/.gitconfig

这一步的目的是让配置 `GOPRIVATE`、`GOINSECURE` 之后 go 走 http 协议下的时候替换成 ssh 协议。

直接用 http 也可以但是需要在 `go mod download` 时输入账密登录。我的 windows git 客户端会报 `terminal prompts disabled` （vscode+remote linux就没事，但windows下各种毛病），所以配成 ssh 之后就免密了，Windows 下少一点麻烦。

```ini
[url "git@<gitlab的ip>:"]
    insteadOf = http://<gitlab的ip>/
```

注意 `url=`后面的`:`别漏了，这样才能拼出 `git@github.com:nnnew/battery` 这样的合法地址。

### 3. 设置 go env

```bash
go env -w GOPRIVATE="<gitlab的ip>"
go env -w GOINSECURE="<gitlab的ip>"
```

设置 `GOPRIVATE` 的目的是让 go 从私有 git 仓库拉代码。

设置 `GOINSECURE` 的目的是让 go 用 http 而不是 https 协议去拉代码。

理论上来说，也可以不设置 `GOINSECURE`，但是 `~/.gitconfig` 里配置 `insteadOf` 的时候要注意写 https 而不是 http，可以自己试试。

### 4. 拉代码

试试 `git clone` 一个私有仓库（http），如果没提示输入账密就成功那就ok了。要是不行就自己搜索下。

理论上来说接下来 `go mod download` 就不会有问题了。

## 总结

重新配了一遍发现还是 Windows 屁事多。