---
title: 安全入门系列-sql注入
slug: get-start-cyber-security-sql-inject
date: 2022-04-19 11:06:00
categories:
- security
tags:
- security
---

## 前言

记得很早以前玩过SQL注入，还在上中学吧好像，拿学校的官网玩。

SQL注入是个很老的漏洞了，准确说是开发人员水平太差、相关的库和最佳实践还没传播开的那段时期常出现的 **编程错误** 。

## 原理

所谓SQL注入就是用户的输入在服务端组织成SQL的时候未经适当地过滤，结果用户输入扭曲了服务端构造的SQL原意，造成错误。

比较常见的一种问题就是直接把用户输入拼接到了SQL字符串里。

```go
func handler(w http.ResponseWriter, req *http.Request) {
    row := db.QueryRow(fmt.Sprintf("SELECT id FROM user WHERE nickname='%s'", req.URL.Query()["nickname"]))
}
```

像是上述的代码，如果用户请求 `localhost/user?nickname=weakptr`，拼接的SQL结果就是`SELECT id FROM user WHERE nickname='weakptr'`，符合预期。但如果用户请求的是`localhost/user?nickname=' UNION SELECT password FROM user WHERE nickname='admin' --`，拼接的SQL就会变成 `SELECT id FROM user WHERE nickname='' UNION SELECT password FROM user WHERE nickname='admin' --`，也就是会查出 `admin` 用户的 `password` 字段。

当然这样的注入并不总是能成功，像是上面我用 go 写的 `QueryRow`，在 `Scan` 的时候传入的变量数量和类型会和被注入的 SQL 不匹配，返回错误。不过这不代表用 Go 就安全了，因为用户完全可以传个 `' DROP TABLE user` 删除整个表，或者拼一个 `' or 1=1` 让条件恒真，跳过身份认证。

对这种问题最好的解决办法就是不要把用户输入直接拼到SQL里，而是用 `?` 占位符。

> https://dev.mysql.com/doc/refman/8.0/en/sql-prepared-statements.html
>
> Using prepared statements with placeholders for parameter values has the following benefits:
>
> - Less overhead for parsing the statement each time it is executed. Typically, database applications process large volumes of almost-identical statements, with only changes to literal or variable values in clauses such as `WHERE` for queries and deletes, `SET` for updates, and `VALUES` for inserts.
> - **Protection against SQL injection attacks. The parameter values can contain unescaped SQL quote and delimiter characters.**

这个特性叫 `server-side prepared statement`，在 MySQL 4.1 就引入了。对更古早一些的开发者来说，想写出现安全的服务端代码确实是没有现如今这么轻松的，还得自己关注SQL拼接和转义。而如今像 Go 这样的语言直接把 `prepared statement` 写进标准库，当成最佳实践，想写出 bug 都不容易。

好了回到正题。

其实硬要说起来 SQL 注入如今也不是完全被杜绝了，因为拼 SQL 始终还是有需求的，对自己代码质量有追求的程序猿还是少数。像是 `SELECT ... FROM tbl WHERE ... IN (a,b,c,d,e,f)`，`IN` 如果要用 `prepared statement` 写就至少要维护一个参数列表和 string builder，但如果像是 python 一类语言，就能偷懒成 `cond.map(lambda s: f"'{s}'").join(',')`，省掉一个参数列表和循环，埋下漏洞。

## 漏洞分类

### 字符型注入

简而言之，提交的输入类型是字符串的时候（比如`nickname`、`address`这样的字段），如果存在上面说的漏洞，那就是一个字符型注入漏洞。

这里涉及的知识点是 **提交的输入类型**。对于弱类型语言来说服务端可能没限制前端表单提交的类型，表单是 `input type=number` 也接受，字符串也接受，服务端的 web 框架要么推导类型（罕见），要么用客户端的类型（当提交`json`一类数据的时候），要么全部当成 `bytes`、`string`，留给开发者自己处理。

比较常规的情况是服务端拿到  `request.form` 是一个字典类型（总之就是`dict`或`map`这样的映射类型，不用抠字眼），值要么全是 `string` 要么根据一定条件解析成服务端的数据类型（`int`、`float`、`array`等）。

如果服务端没有解析类型，直接往 SQL 里拼，大多时候就是字符型SQL注入；解析了，是个字符串，往 SQL 里拼，也是字符型注入。

解析了，不是字符串，再格式化，那就很难控制服务端的SQL了。

### 数字型注入

数字型注入就是放屁。

本质依然是你提交的数据没有被服务端检查类型，不管是 `int` 还是 `string` 直接往 SQL 里拼。非要说和字符型注入的区别就是服务端怎么把自己觉得是数字的内容拼到 SQL 里：

- `WHERE nickname='{nickname}'` 拼字符串的时候为了不出现SQL语法错误，要加上 `''` 单引号。
- `WHERE id={id}` 拼数字的时候就不加。

但凡用 `sprintf`格式化个`%d`，或者拿什么请求验证框架对输入数据做了个类型检查就没数字型注入什么事儿了。

## 注入点

### query

就是出现在 URL Query Parameter 里的 SQL 注入点。比如 `GET /user_profile?user_id=1`，`user_id=1`没过滤，那注入点就在这里。

### post

出现在 post 表单里的注入点，`content-type` 是 `x-www-form-urlencoded` 还是 `multipart/form-data`，亦或者 `application/json` 都无关紧要。

只要服务端的代码无脑往 SQL 里拼用户输入，那就是注入漏洞。

### header

出现在 HTTP Header 里的注入点，比如在 `Cookies` 的什么数据，或者自定义的 HTTP 头字段。牢记 SQL 注入漏洞的本质是服务端拿了这些数据无脑往SQL里拼。

## 攻击手法

### 报错法

首先从攻击者的视角看肯定是不知道服务器上数据表怎么设计的，所以一上手就直接传个 `' UNION SELECT` 查出管理员账号密码是不太现实的。

当通过传 `' or 1=1` 或类似的 payload 确认可能存在 SQL 注入点之后，攻击者可以故意制造一些 SQL 错误，看看服务端有没有直接把错误页返回到浏览器。

如果服务端没有做好 500 页面处理，直接把面向开发者的错误信息返回给了攻击者，攻击者就能借此获得服务端的信息：比如服务端使用的编程语言、框架、数据库版本、表名等等。如果错误页再人性化一点，比如类型错误顺便打印出变量内容，直接把数据爆出来也有可能。

没管好 500 页导致错误爆到前端，这种问题也可能造成 SQL 注入以外的漏洞但不是这篇博客想讨论的内容了。

总之报错法攻击就是根据返回的错误信息调整注入的payload，最终构造合法的 SQL 查出攻击者想要的数据。

### 盲注

对于没有 500 页（注入非法SQL不报错）或者只有一个通用的 500 页（不返回具体错误），此时只能盲注。先确定注入的 SQL 会如何影响页面，比如提交合法 payload 时的页面和提交非法 payload 时的页面有何不同。相当于我们有了一个 bit 的观测窗口。

接着只要构造一个合法的 SQL ，比如 `' AND username=admin` 等（例子不好，控制了 SQL其实能干的事情太多了）就能一个字符一个字符爆破出用户名和密码（前提是密码没加盐哈希）。

### 读写文件

比如服务器运行的是MySQL而且权限配置有问题（比如跑在 root），那就可能直接注入一条 `LOAD_FILE/OUT_FILE` 之类的函数，写入 Web Shell 或者读到 `/etc/shadow` 之类的敏感文件。

## 工具

- sqlmap

只知道这一个。

## 总结

现在 SQL 注入的漏洞应该不多了，大概还有些被玩烂了的旧网站依然有这种问题。按现在挖矿的疯狂程度来看，还有这种洞怕是迟早被淦，要么下线要么升级。

现代的 web 程序这种问题应该不多了，有好用的 ORM 和各种查询工具还手拼 SQL 干啥呢。

挖 ORM 或者那些查询库的洞就是另一码事了。