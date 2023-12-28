---
title: 升级公司的 GitLab
date: 2021-07-15 16:02:41
tags:
  - linux运维
categories:
  - linux运维
---

公司目前跑的 gitlab 是很久以前部署的，当前版本 _8.4.2_ 。升级目标是 _13.12.Z_ 。部署方式是 docker 。

<!-- more -->

宿主机配置不高，系统 _Ubuntu 15.04_ 。眼下这个时间，这个Ubuntu版本，基本宣告没法用了。直接在线升级容易把引导搞挂，到时候还得亲自去实体机上折腾引导，麻烦。暂时不管宿主机。

## 情况概述

因为 GitLab 版本实在太低了，以至于连一个能集成的 CI/CD 工具都找不到。即使 jenkins 都只能很勉强地动起来，偏偏 jenkins 还不能满足需要（也可能是我太菜，反正公司没人玩得转 jenkins）。

但开发需要 CI/CD 来解决持续构建和部署的问题，不得不考虑升级了。

## 1. 备份

什么都别说了，开干前最重要的事情就是备份，免得把自己玩死。

最常用的备份手段自然是 `tar` 。不过 gitlab 数据目录实在太大了，要是直接运行 `tar -czpf gitlab.tar.gz ./gitlab` 不知道跑多久，也不知道有没有卡死。

于是上技术手段：用 `pv` 显示个进度条。

pv 项目的首页在 [ivarch.com](http://www.ivarch.com/programs/pv.shtml)。因为服务器还在跑*ubuntu 15.10*，现在连个能用的源都没啦。只好下载了源码，在 wsl 里编译好推上去。

最终命令如下。

```bash
sudo tar cf - ./gitlab -P | pv -s $(sudo du -sb ./gitlab | awk '{print $1}') | gzip > gitlab.tar.gz
```

为啥 sudo 呢，postgres 数据库和 redis 数据都没有读权限，没辙。

## 2. 升级总体思路

gitlab 的手册还是比较全面的。在[upgrading to a new major version](https://docs.gitlab.com/ee/update/index.html#upgrading-to-a-new-major-version) 这篇文档提到的说法，跨大版本升级主要分三步：

1. 升级至当前大版本(_major version_)的最新小版本(_latest minor version_)
2. 升级至目标大版本(_target major version_)的首个小版本(_first minor version_)
3. 继续升级至更新的版本

根据 [gitlab upgrading guide 的说法](https://docs.gitlab.com/ee/update/index.html#upgrades-from-versions-earlier-than-812)，版本低于 _8.11.Z_ 时，先更新到 _8.12.0_ 是比较稳妥的方案。

so 开干。

## 3. 升级至 8.12.0

由于部署方式是 docker（准确的说是 docker-compose），所以按照[Update GitLab Using Docker Engine](https://docs.gitlab.com/ee/install/docker.html#update-gitlab-using-docker-engine) 的说法，我们先停止容器，然后直接修改镜像标签。

```bash
docker-compose stop
```

```yaml
gitlab:
  restart: always
  image: sameersbn/gitlab:8.12.0 # <= sameersbn/gitlab:8.4.2
```

再启动

```bash
docker-compose up -d
```

### 故障：GITLAB_SECRETS_OTP_KEY_BASE must set

使用的镜像 `sameersbn/docker-gitlab` 需要这几个环境变量，[参考文档](https://github.com/sameersbn/docker-gitlab#quick-start)完成设置。

### 故障：You must enable the pg_trgm extension

这个故障就比较奇怪了，但还是可以处理。

先设置一下 postgres 账号密码

```bash
docker exec -it gitlab_postgresql_1 psql -U postgres
```

然后

```sql
\password postgres
```

输入新密码，按 ctrl+d 退出。

再用随便啥连接上去，运行 `create extension pg_trgm;` 就完事了。

最后就是重启下容器，gitlab 自动迁移完成后即可访问。

## 4. 升级至 v8.17.4

原本应该升级到 v8.17.7，但 `sameersbn/docker-gitlab` 没提供这个版本的镜像，只能先升级到 v8.17.4 ，求老天保佑别折腾出问题。

老规矩改了 docker-compose ，然后 up 。

直接成功，没有错误。

## 5. 升级至 v9.5.5

老规矩，还是缺少镜像，原本应该升级到 v9.5.10。

改了 docker-compose 再 up。

成功。

## 6. 升级至 v10.8.4

原本应该升级 v10.8.7 。懒得说了。改了 compose 再 up 。

### 故障：This probably isn't the expected value for this secret

错误内容

```text
This probably isn't the expected value for this secret. To keep using a literal Erb string in config/secrets.yml, replace &lt;%with&lt;%%.
```

不知道为什么，重启了一次容器后就恢复了。

可以参考下[这个](https://github.com/sameersbn/docker-gitlab/issues/1625)。

## 7. 升级至 v11.11.3

根据 v12 的升级指引，

> In 12.0.0 we made various database related changes. These changes require that users first upgrade to the latest 11.11 patch release.

必须先升级到 v11.11.Z 版本，再升级 v12.0.Z 才能完成数据库迁移。

于是先升级到 v11.11.3 (也是因为没有 v11.11.8 的镜像)。

成功。

## 8. 升级至 v12.0.4

根据 12.0 升级指引，先升级到 12.0.Z 版本来完成 11->12 的迁移，再继续升级。

成功。

## 9. 升级至 v12.1.6

根据 12.1 升级指引，在升级到 12.10.Z 之前，必须先升级到 12.1.Z 。

> If you are planning to upgrade from 12.0.Z to 12.10.Z, it is necessary to perform an intermediary upgrade to 12.1.Z before upgrading to 12.10.Z to avoid issues like #215141.

成功。

## 10. 升级至 v12.10.6-1

缺少最新的 12.10.Z 镜像，先升级到能升级到的 12.10.Z 最高版本。

成功。

## 11. 升级至 v13.0.6

这个版本对 postgres 数据库版本有要求，故升级 postgresql 到 9.6.4 版本。镜像自动完成了数据迁移。

之后启动 gitlab 完成升级。

成功。

## 12. 升级至 v13.12.4

这个版本对 postgres 数据库版本又有要求，最低在 11 以上，故升级 postgresql 到 11-20200524 (sameersbn/postgresql)。

同时，需要安装插件 `btree_gist`，故连接 postgresql 数据库创建。

```sql
create extension if not exists btree_gist;
```

之后启动 gitlab 完成升级。

## 13. 总结

由于 gitlab 设计良好，升级基本没有太大难度。按照文档的升级路线逐个版本升级即可。

也是我运气好，在升级 10.8.Z 版本的时候遇到的问题重启后自己消失了，不然光是这个问题可能就要折腾很久。

最终 gitlab 版本停留在 13.12.Z ，14.0 虽然已经发布了，但出于稳定考虑还是先不升级。
