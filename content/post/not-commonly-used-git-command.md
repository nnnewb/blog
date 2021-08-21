---
title: 不常用的 Git 命令
date: 2021-07-09 09:25:16
tags:
- git
categories:
- git
---

大概是不太常用的一些 Git 命令。

<!-- more -->

## 找回数据

两种办法：

```bash
git reflog show
git reset --hard HEAD@{1} # 从上一步找到希望回退的位置
```

或者

```bash
git fsck --lost-found
cd .git/lost-found/
# 用 git show hash 查看悬空对象的内容
# 用 git merge hash 或者 git rebase hash 来恢复到当前分支里
```

## 合并分支时创建合并commit

```bash
git config branch.master.mergeoptions "--no-ff"
```

## 删除远程分支

```bash
git push --delete origin branch
```

## 删除已经合并的分支

[参考](https://stackoverflow.com/questions/6127328/how-can-i-delete-all-git-branches-which-have-been-merged)

### 删除已合并的本地分支

```bash
git branch --merged \
    | grep -E "^\\s+(patch|feat|refactor|test|misc)" \
    | xargs -I{} git branch -d {}
```

### 删除已合并的远程分支

```bash
git branch -r --merged \
    | grep -E "^\\s+origin/(patch|feat|refactor|test|misc)" \
    | sed 's/origin\///' \
    | xargs -I{} echo git push --delete origin {}
```


