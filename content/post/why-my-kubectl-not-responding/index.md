---
title: 排查一个kubectl无反应的问题
slug: why-my-kubectl-not-responding
date: 2021-12-27 15:21:00
categories:
- kubernetes
tags:
- linux运维
- kubernetes
---

懒得分段了，就当做是讲个故事吧。

背景大概是这样。

内网公共开发机上配置了 k3s 集群，同时后端开发工作也在这台开发机上进行（通过vscode remote-ssh）。因为公司太抠门，开发机只有117G硬盘容量，除去必要的开发工具、系统环境之类的东西，实际可用一直没超过50%，机器上又跑了很多东西，像是 gitlab-runner、docker的registry、MySQL、elasticsearch、开发集群服务等等，差不多每一两个星期都会出现 disk-pressure 的 taint，导致 pod 被 evicted。实话说能跑就很满足了，毕竟公司抠门到开发部门的上行带宽都贼小，如果把镜像推送到公网的registry去部署的话体验更差。

今天（周一）来公司之后调了下gitlab-ci，给一个前端项目做持续部署。因为前端对kubernetes这套不熟悉，也没有相关的服务器权限，总之就是很难让他们自己来。但是产品部门又喜欢提那种“按钮移到右上角”、“加个图片”之类的需求（对，我司还没有需求管理系统，开发就是个撸码的无情工具人），前端老是过来找我去部署下环境，就搞得摸鱼都摸不痛快。

所以，当当当~当~，整一个持续部署呗，反正是个纯前端项目，不用部署配套的后端代码，写个dockerfile再写个helm chart就差不多了，ci调了调构建镜像就完事，不过因为ci部署需要访问集群，所以又改了下`.kube/config`，删了之前尝试`csr`方式添加用户的时候加多的 user 和 context ，复制了一份挂载到 runner 容器里。

然后......问题就来了。

同事忽然告诉我办公室的服务挂了，于是下意识地打出`kgp`，卡住。

等了一会儿，还是卡住。

又等了一会儿，坐不住了。试了下`kubectl cluster-info`，继续卡住。

开始慌了，想起今天的机器有点卡，先看看 `free -h` 有没有内存泄漏之类的问题导致阻塞，结果发现并没有，于是继续看 `htop`，cpu使用率也比较正常。再看`df -h | grep -vE 'shm|overlay'`，发现硬盘使用率96%（估计硬盘主控想死的心都有了，揪着4%的可用空间想把PE数平均到各个区块恐怕不容易）。

找到问题后松了口气，十有八九是又出现 evicted 了。二话不说直接 `docker system df`，看到30多G的 build cache 顿时惊了，肯定不是go的构建缓存（手动挂载优化了），那就是 node_modules 又立奇功了。node_modules=黑洞果然不是吹的。

清理完使用率恢复到63%，但依然有种不安感萦绕于心，于是再次尝试`kgp`，卡住。

等了一会儿，喝口水，继续卡着。

又等了一会儿，淦。

想了想，`journalctl -r -u k3s`看看日志，并没有什么发现，倒是注意到很多`linkerd`之类的我们部门经理搞事的时候遗留下来的玩意儿在报错，service mesh 我不熟，但寻思应该不会影响 kubectl 吧，k3s 本体的 api-server 应该不归 linkerd 管。更何况 linkerd 本身就没配好。再翻了翻看到下面的内容。

```log
    6 12月 25 21:16:07 office k3s[794]: I1225 13:16:07.685149     794 container_gc.go:85] attempting to delete unused containers
    7 12月 25 21:16:07 office k3s[794]: I1225 13:16:07.687723     794 image_gc_manager.go:321] attempting to delete unused images
    8 12月 25 21:16:07 office k3s[794]: I1225 13:16:07.782390     794 eviction_manager.go:351] eviction manager: able to reduce ephemeral-storage pressure without evicting pods.
    9 12月 25 21:16:17 office k3s[794]: W1225 13:16:17.939242     794 eviction_manager.go:344] eviction manager: attempting to reclaim ephemeral-storage
   10 12月 25 21:16:17 office k3s[794]: I1225 13:16:17.939267     794 container_gc.go:85] attempting to delete unused containers
   11 12月 25 21:16:17 office k3s[794]: I1225 13:16:17.941771     794 image_gc_manager.go:321] attempting to delete unused images
   12 12月 25 21:16:18 office k3s[794]: I1225 13:16:18.033724     794 eviction_manager.go:351] eviction manager: able to reduce ephemeral-storage pressure without evicting pods.
   13 12月 25 21:16:28 office k3s[794]: W1225 13:16:28.214032     794 eviction_manager.go:344] eviction manager: attempting to reclaim ephemeral-storage
```

这个是老问题了，一直没去研究怎么解决。

```log
  154 12月 25 21:21:55 office k3s[794]: I1225 13:21:55.021937     794 image_gc_manager.go:304] [imageGCManager]: Disk usage on image filesystem is at 95% which is over the high threshold (85%). Trying to free 182  155 12月 25 21:21:55 office k3s[794]: E1225 13:21:55.025140     794 kubelet.go:1292] Image garbage collection failed multiple times in a row: failed to garbage collect required amount of images. Wanted to free
```

这次搜了下，应该是 `docker system prune` 造成 `kubelet` 找不到可回收的镜像才报错（猜测），不过依然不能解释为啥 `kubectl` 没反应。于是继续翻了会儿日志，搜索错误，但始终没有什么结果。

但是同事还要干活，没辙了，先重启下服务器吧。群里说了一声要重启了，等了一会儿跑`sudo reboot`，重启完连接，继续`kgp`，卡住。

嗯......

早有预料。

`journalctl -r -u k3s --boot` 看看重启后的日志，发现还是老一套的问题，`docker` 手动处理镜像和容器造成的和 kubernetes 的管理机制的冲突，各种找不到镜像或者容器的警告，还有一些错误和trace，但没有一个能解释为什么`kubectl`没有反应。。。

直到在`kubectl`的终端里按下了ctrl+c，在顺手`clear`之前看到了一行请输入用户名（eng）...

警觉。

忽然想起来，因为 `kubectl` 这破玩意儿是没有颜色输出的，用习惯了各种彩色输出的命令行工具，`kubectl`就格外不顺眼。所以在发现`kubecolors`后，我就直接把`kubectl`配置成了`kubecolor`的别名。

所以......难道是`kubecolor`的问题？

`whereis kubectl`找到`kubectl`的绝对路径之后，尝试手动运行`/usr/local/bin/kubectl cluster-info`，再次出现了那个输入用户名的提示，顿时开始怀疑起`.kube/config`配置有问题，正好在出现问题之前改过了`.kube/config`，这里出问题的嫌疑就很吉尔大。

于是打开`.kube/config`，检查了一下集群的用户配置，发现果然，是我手欠把办公室集群的用户给删了。草。

急忙从`/etc/rancher/k3s/k3s.yaml`复制下用户证书配置，贴进去，再运行`kgp`果然屁事没有了。

所以总结如下。

1. 别被表面的问题迷惑。
2. 自己犯傻的几率大于基础设施/常用工具犯傻的几率。
3. 遇到问题解决步骤很重要，准确的方向可以省很多时间。
   1. 先确定故障表现和复现条件
   2. 确定故障点（出现在网络、网关还是应用、数据库），弄清楚是不是新问题
   3. 再排查相关配置是否正确，回忆是否有做过相关修改变更
   4. 再排查故障点日志，必要的时候参考下代码，毕竟有的时候日志没写清楚错误的上下文