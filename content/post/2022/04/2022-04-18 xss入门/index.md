---
title: 安全入门系列-xss
slug: xss-day-1
date: 2022-04-18 10:11:00
categories:
- security
tags:
- security
- js
- xss
---

## 前言

要是开发拿不到更高薪，继续撞天花板，就打算转安全了。考虑5年开发，以及不止5年的各种学习，想转到安全应该不是太难的事。

且不说转不转行，先了解下安全这行总没错。不转行懂点安全也算优势。

> 编辑于 2022年4月19日

考虑成体系学习，把标题改成了安全入门系列。差不多弄清楚 web 安全主流的攻防方向之后再整理个脑图什么的梳理下怎么深入。

## XSS

### 原理

XSS全称 Cross Site Scripting，X 就是 Cross（强行冷笑话）。本质是利用不正常的方式，在网页上插入一段可以执行的 JavaScript 代码，实现窃取 Cookie、冒充用户发送请求之类的操作。

众所周知浏览器按 F12 在开发者工具里想怎么玩弄网页都行，XSS 听起来像是脱裤放屁。但开发者工具是有极限的，骗人打开开发者工具往里面贴自己看不懂的代码，和发个链接一打开就中招显然是两个难度的事情。

### 分类

#### 反射型

反射型 XSS 利用服务器或前端把请求中的字段渲染成 HTML 的行为来向网页注入 js。比如这样一个页面：

```php
<p> 你好，<?php echo $_GET["name"]?></p>
```

页面元素的一部分未经过滤就直接渲染成了 HTML 的一部分，就会产生一个 XSS 漏洞，传递这样一个 `name` ： `<img src=1 onerror=alert(1)/>` 就能让网页按我们的想法弹窗了。

之所以叫反射型，是因为注入的 JS 到了服务器又回到了前端，就像是镜子里反射出你自己的影子。

#### 持久型

和反射型差不多，不同的是注入的 JS 被持久化到了服务端，比如上面的用户名注入点是从数据库提取的，那么把用户名改成 `<img src=1 onerror=alert(1)/>`，每次访问这个页面都会触发脚本了，威胁比反射型 XSS 更大。

#### DOM型

DOM 型和上面其他 XSS 的主要区别在于不经过服务器，像是现在大前端常见的 SPA ，路由都在前端，后端只有 API 不负责渲染网页。如果前端应用里出现 `elem.innerHTML=userinput`，`userinput`没好好过滤的情况，就是个 DOM 型的 XSS 漏洞。

### 测试

#### 代码审计

目前对代码审计的理解就是 review 源码来尝试发现漏洞，大概只对开源代码或前端代码有用。没代码的话审计就有点逆向的意思了。XSS 漏洞可以从审计中发现，比如 [一次对 Tui Editor XSS 的挖掘与分析](https://www.leavesongs.com/PENETRATION/a-tour-of-tui-editor-xss.html)。

#### 手动测试

手工测试就是在可能的 XSS 注入点提交诸如 `<img/onerror=alert(1)>`一类的内容，观察提交的内容是怎么转义的，提交内容如何渲染，再尝试修改 payload 来绕过防护，直至成功或失败。

#### 自动测试

尚不清楚自动 XSS 测试的原理，工具有 [XRay](https://github.com/chaitin/xray) 。个人猜测至少两条路子：

1. 对能访问源码的情况可以自动源码审计，找出危险的赋值或调用。
2. 不能访问源码的情况下：
   1. 尝试判断底层框架，使用已知漏洞的 exploit 测试
   2. 根据一定的规则，在可能的表单提交点尝试一系列 payload

实际上我觉得更像是半自动的，比如不涉及源码的情况下至少应该需要配置下要尝试的注入点（以及如何检测注入是否成功的页面）和指定 payload 类型，不然注入点的表单都填不满。

## 总结

我倒是想再加个实战环节，但现在找个足够简单的 XSS 还挺难的。vulhub 有个 drupal 的 XSS 虽然能跑，但单纯跑一下 PoC 着实没什么乐趣可言。重复一次别人做过的分析倒是可以，但有点超出写这篇博客时的计划了，于是暂时不管，走马观花为主，先对整个安全体系建立概念再由点带面入门。