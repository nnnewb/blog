---
title: 处理一个git问题
date: 2023-03-21 17:07:50
categories:
- git
tags:
- git
---

## 现象

环境：Windows+Git 2.39.1 (scoop 安装，git-with-openssh)

在 clone 仓库的时候报错。

```
Enumerating objects: 27, done.
Counting objects: 100% (27/27), done.
Delta compression using up to 16 threads
Compressing objects: 100% (24/24), done.
Writing objects: 100% (25/25), 187.79 KiB | 9.39 MiB/s, done.
Total 25 (delta 1), reused 0 (delta 0), pack-reused 0
send-pack: unexpected disconnect while reading sideband packet
fatal: the remote end hung up unexpectedly
```

提取关键词 `send-pack: unexpected disconnect while reading sideband packet`

## 分析

不太可能是 SSH 层面的错误。

之前遇到过奇怪的问题，git 客户端版本可能有影响。

搜索 StackOverflow 找到相关问答：[Github - unexpected disconnect while reading sideband packet](https://stackoverflow.com/questions/66366582/github-unexpected-disconnect-while-reading-sideband-packet)

## 尝试

### 环境变量

```powershell
$env:GIT_TRACE_PACKET=1
$env:GIT_TRACE=1
$env:GIT_CURL_VERBOSE=1
```

结果：**不行**

### 配置 `http.postBuffer`

```bash
git config --global http.postBuffer 157286400
```

结果：**不行**

### core/pack 配置

```ini
[core] 
    packedGitLimit = 512m 
    packedGitWindowSize = 512m 
[pack] 
    deltaCacheSize = 2047m 
    packSizeLimit = 2047m 
    windowMemory = 2047m
```

结果：**不行**

### 先浅clone再fetch

```bash
git config --global core.compression 0
git clone --depth 1 <repo_URI>
git fetch --unshallow 
```

结果：可以 clone 但是不能 fetch ，报错相同。**不行**。

### 配置 `pack.window`

```bash
git config --global pack.window 1
```

和

```ini
[core] 
    packedGitLimit = 512m 
    packedGitWindowSize = 512m 
[pack] 
    deltaCacheSize = 2047m 
    packSizeLimit = 2047m 
    windowMemory = 2047m
```

搭配，问题消失。

结果：略作变更，**可行**。

## 另一种办法：降级

把 git 降级到2.19.2，不修改配置，也能正常 clone 。

因为[git-scm.com](git-scm.com)没放开下载历史版本（那个 older release 里没有Windows安装包），所以需要手动改下正常下载的 url 。

```
https://github.com/git-for-windows/git/releases/download/v2.19.2.windows.1/Git-2.19.2-64-bit.exe
把这个链接的 2.19.2 改成想下载的版本，如果文件还在的话就能正常下了。
```

当然看这个 url 也可以选择从 github 下载，直接打开项目地址然后找 release 就ok。

## 结论

两种办法解决

1. 修改 `~/.gitconfig`，内容
   ```ini
   [core] 
       packedGitLimit = 512m 
       packedGitWindowSize = 512m 
   [pack] 
       deltaCacheSize = 2047m 
       packSizeLimit = 2047m 
       windowMemory = 2047m
       window = 1
   ```

2. 降级 git 到 1.19.2 （或者别的版本，二分法）

