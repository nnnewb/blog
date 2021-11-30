---
title: 简单的ECK部署
slug: simple-ECK-cluster-deployment
date: 2021-11-30 11:13:00
categories:
- kubernetes
tags:
- linux运维
- kubernetes
- elasticsearch
---

## 前言

因为工作需要，得在自己搭建的集群里部署一个 Elasticsearch 。又因为是云端的集群，在 k8s 外用 docker 单独起一个 ES 明显更难维护（但部署更简单），于是选择用 ECK 。

ECK 就是 Elastic Cloud on Kubernetes 的缩写，可以理解成部署在 Kubernetes 上的 Elasticsearch 。当然不止 ES 。

部署 ES 的过程遇到几个问题记录下怎么解决的。

1. ES 使用自签名证书，导致 HTTP 不能连接。
2. ECK 需要安装 IK 分词插件。
3. ECK 默认密码每次部署都重新生成，而且默认用户权限过大。
4. ECK 默认没配 PVC ，数据没有持久化。

接下来逐个解决。

## 0x01 自签名证书

自签名证书解决方法有几个

1. 改客户端，让客户端用自签名证书连接。很麻烦。
2. 生成一个固定的证书，让ES和客户端都用这个证书，客户端和ES都要改。很麻烦。
3. 禁用 ES 的自签名证书。

考虑到是私有的测试环境，不搞这些烦人的东西，直接禁用。

修改 YAML 如下。

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
spec:
  http:
    tls:
      selfSignedCertificate:
        disabled: true
```

注意 `spec.http.tls.selfSignedCertificate.disabled` 这个字段。

参考文档：[Orchestrating Elastic Stack applications - Access Elastic Stack services - TLS certificates](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-tls-certificates.html)

## 0x02 安装 IK 分词组件

官方文档提供的安装插件思路是利用 initContainer 。参考文档：[init containers for plugin downloads](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-init-containers-plugin-downloads.html) 。

```yaml
spec:
  nodeSets:
  - name: default
    count: 3
    podTemplate:
      spec:
        initContainers:
        - name: install-plugins
          command:
          - sh
          - -c
          - |
            bin/elasticsearch-plugin install --batch repository-gcs
```

initContainer 容器默认会继承自下面的内容：

- 没有另外指定的情况下，继承主容器的镜像(我的例子中，就是 `Elasticsearch:7.9.1`)
- 主容器的 volume 挂载，如果 initContainer 有同名同路径的 volume 则优先用 initContainer 的。
- POD 名称和 IP 。

## 0x03 添加自定义用户

有好几种方式：

1. 官方文档中的方法：[k8s users and roles](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-users-and-roles.html)，比较稳定，但还是挺麻烦的。
2. 修改 `[es-cluster-name]-es-elastic-user` 这个 `secret`，好处是简单，但要求必须先创建 secret 再创建 ES ，单个 YAML 去 `create -f` 的情况下不友好。
3. 基于第2节中利用 initContainer 的做法和官方文档里提到的 `elasticsearch-users` 命令行工具，直接在 initContainer 里创建指定用户名密码的用户。不确定这个做法会不会在多节点 ECK 里出问题，毕竟这等于是每个节点都创建了一次用户。不过我只需要单节点，所以也还过得去。

最终决定用第 3 种方法，因为做一个单节点集群简单不费事，多节点的话，目前开的服务器配置也吃不消。（其实是搞完才仔细读文档，第 1 种方法其实也不算太麻烦...）

```yaml
spec:
  nodeSets:
  - name: default
    count: 3
    podTemplate:
        spec:
          initContainers:
          - name: donviewclass-initialize
            command:
            - sh
            - -c
            - |
              ./bin/elasticsearch-plugin install -batch https://ghproxy.com/https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v7.9.1/elasticsearch-analysis-ik-7.9.1.zip
              ./bin/elasticsearch-users useradd tsdonviewclass -p tsdonviewclass -r superuser
```

`./bin/elasticsearch-users useradd tsdonviewclass -p tsdonviewclass -r superuser` 主要就是增加这一句。同样是因为懒，权限直接给了 superuser 。

参考文档：[elasticsearch-users](https://www.elastic.co/guide/en/elasticsearch/reference/current/users-command.html) 。

## 0x04 配置PVC

依然是参考官方文档来：[k8s-volume-claim-templates](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-volume-claim-templates.html)。

```yaml
spec:
  nodeSets:
    - name: default
      count: 1
      config:
        node.store.allow_mmap: false
      volumeClaimTemplates:
        - metadata:
            name: elasticsearch-data # Do not change this name unless you set up a volume mount for the data path.
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 5Gi
            storageClassName: local-path
```

注意 `volumeClaimTemplates` 下 `metadata.name` 不要变，除非你自己在 `podTemplate` 里覆写挂载字段。

其他的 `spec` 下内容和通常的 PVC 一样，可以参考 [Kubernetes - PersistentVolumeClaims](https://kubernetes.io/zh/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims) 。

值得注意的是 ECK 默认在集群节点数量 scaled down 时删除 PVC ，对应的 PV 可能保留，具体看[存储类的回收策略](https://kubernetes.io/docs/concepts/storage/storage-classes/#reclaim-policy)。ECK 的 CRD 里也给了相关的配置项。

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: es
spec:
  version: 7.15.2
  volumeClaimDeletePolicy: DeleteOnScaledownOnly
  nodeSets:
  - name: default
    count: 3
```

注意 `volumeClaimDeletePolicy: DeleteOnScaledownOnly` 。可选的策略包括：

- `DeleteOnScaledownAndClusterDeletion`
- `DeleteOnScaledownOnly`

默认策略是 `DeleteOnScaledownAndClusterDeletion` ，集群删除和 scaled down 时删除 PVC。

如果是一次性的部署，可以直接用 `emptyDir` 作为存储类，不用管数据丢不丢。

## 总结

这几步配置下来，一个开发用的 ES 集群就算是配完了，资源给够就能开始玩了。

讲道理我不太会运维 ES 啊，ES 这东西实在有点重量级，现阶段的能力也就只能看文档这里那里配一下，在上面开发什么的。真要遇到大问题还得抓瞎。

就先这样吧。