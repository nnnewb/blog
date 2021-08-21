---
title: csr 方式创建 kubernetes 用户出了点差错
date: 2021-07-19 09:52:38
tags: ["kubernetes", "devops"]
categories: kubernetes
references:
  - title: 证书签名请求 | kubernetes
    url: https://kubernetes.io/zh/docs/reference/access-authn-authz/certificate-signing-requests/#normal-user
---

越是在 kubernetes 的浑水里摸索，越是发现这就是个不顺手的锤子。

网上很多人喜欢把东西用不惯叫做懒，蠢，要是多反驳几句，那就还得搭上个“坏”的帽子。感觉吧，就这帮人看来，大神放个屁也值得学习，从里面“悟”出什么道理。

这帮人就跟传教士一样，但凡说个不字，就是在亵渎他们的“大神”。可谓人类迷惑行为。

好吧。技术别饭圈化行吗？

你说尤大强吗？Richard Stallman 是不是值得尊敬？Google 是不是最好的技术公司？Android 天下无敌？

然后全摆上神坛，挂上赛博天神的牌匾，插上网线一天 25 小时膜拜？

这帮人哪天搞个崇拜互联网和计算机的教派，把冯·诺依曼奉为先知我都不奇怪。

拜托，你们真的好怪欸。

<!-- more -->

## 完整脚本

```bash
#!/bin/bash -e
#
# 创建用户 gitlab 并授予权限
#
# reference:
# https://kubernetes.io/zh/docs/reference/access-authn-authz/certificate-signing-requests/#normal-user

# if `gitlab` does not exists,
# create csr and approve
if ! kubectl get csr gitlab >/dev/null; then
    # create credential
    if [ ! -f gitlab.csr ]; then
        openssl genrsa -out gitlab.key 2048
        openssl req -new -key gitlab.key -out gitlab.csr
    fi

    csr=$(cat gitlab.csr | base64 | tr -d "\n")
    cat <<EOF | tee gitlab-csr.yaml
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: gitlab
spec:
  groups:
  - system:authenticated
  request: $csr
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF
    kubectl create -f gitlab-csr.yaml
    kubectl certificate approve gitlab
fi

# get signed credential
kubectl get csr gitlab -o jsonpath='{.status.certificate}'| base64 -d > gitlab.crt

# create role and rolebinding
kubectl create role gitlab-ci \
    --verb=create \
    --verb=git \
    --verb=list \
    --verb=update \
    --verb=delete \
    --resource=pods \
    --resource=deployment \
    --resource=statefulset \
    --resource=service \
    --resource=configmap
kubectl create rolebinding gitlab-ci-binding-gitlab --role=gitlab-ci --user=gitlab
kubectl config set-credentials gitlab --client-key=gitlab.key --client-certificate=gitlab.crt --embed-certs=true
kubectl config set-context ci --cluster=office --user=gitlab --namespace=version4
```

## 存在的问题

脚本跑完后发现还不能使用 `kubectl get pods`，错误 Unauthorized。

再看了一遍文档，发现有这么一句。

> 下面的脚本展示了如何生成 PKI 私钥和 CSR。 设置 CSR 的 CN 和 O 属性很重要。CN 是用户名，O 是该用户归属的组。 你可以参考 RBAC 了解标准组的信息。

顺着链接去看了下 RBAC，结果也没找到什么“标准组”。

对于文中说的两个“很重要”的字段，CN 我猜测是 Common Name，O 就是 Organization。现在就不知道怎么填 O，行吧。

等啥时候搞清楚了再补一篇。
