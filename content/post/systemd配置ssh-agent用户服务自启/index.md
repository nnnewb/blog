---
title: systemd 配置 ssh-agent 用户服务自启
date: 2022-06-27 11:17:00
categories:
- 杂谈
tags:
- 杂谈
- linux
- ssh-agent
---

## 前言

主要是想解决一个问题：ssh 只自动尝试了 `~/.ssh/id_ed25519` 这个硬编码的路径，但我有两个 ed25519 秘钥（工作用一个，私人一个），除非用 `ssh -i` 指定不然不会被自动发现和使用。

但我又不想多打个 `-i ~/.ssh/id_ed25519.xxx` ，所以就想配个 `ssh-agent` 好了，手动`ssh-add` 还是自动都可。

## 配置

### 创建服务配置

位置：`~/.config/systemd/user/ssh-agent.service`

内容

```ini
[Unit]
Description=SSH key agent

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket
ExecStart=/usr/bin/ssh-agent -D -a $SSH_AUTH_SOCK

[Install]
WantedBy=default.target
```

添加 `SSH_AUTH_SOCK DEFAULT="${XDG_RUNTIME_DIR}/ssh-agent.socket"` 到 `~/.pam_environment`。

在我的系统上 `XDG_RUNTIME_DIR` 对应 `/run/user/你的用户id` ，不同发行版自己看下这个全局变量对应哪个位置。

```bash
echo SSH_AUTH_SOCK DEFAULT="${XDG_RUNTIME_DIR}/ssh-agent.socket" | tee -a ~/.pam_environment
```

可选，自动添加秘钥（OpenSSH版本>=7.2）：

```bash
echo 'AddKeysToAgent  yes' >> ~/.ssh/config
```

### 启用服务

```bash
systemctl --user enable ssh-agent
systemctl --user start ssh-agent
```

重新登录后生效。

## 总结

参考：[How to start and use ssh-agent as systemd service?](https://unix.stackexchange.com/questions/339840/how-to-start-and-use-ssh-agent-as-systemd-service)

