---
title: MySQL XA 事务和分布式事务处理模型：2阶段提交
slug: mysql-xa-distributed-transaction-processing-model-2pc
date: 2021-07-09 09:29:22
tags:
- mysql
categories:
- sql
---

关于 MySQL XA 事务和 2PC（两阶段提交）分布式事务处理模型（*Distributed Transaction Processing, DTP Model*）的学习笔记。

<!-- more -->

## 事务

### 分布式事务XA

#### 介绍

MySQL内建分布式事务支持（`XA`），参考文档列出如下

- [MySQL Manual - XA]([MySQL :: MySQL 8.0 Reference Manual :: MySQL Glossary](https://dev.mysql.com/doc/refman/8.0/en/glossary.html#glos_xa))
- [MySQL Manual - XA Transaction]([MySQL :: MySQL 8.0 Reference Manual :: 13.3.8 XA Transactions](https://dev.mysql.com/doc/refman/8.0/en/xa.html))
- [MySQL Manual - XA Transaction Statements]([MySQL :: MySQL 8.0 Reference Manual :: 13.3.8.1 XA Transaction SQL Statements](https://dev.mysql.com/doc/refman/8.0/en/xa-statements.html))
- [MySQL Manual - XA Transaction State]([MySQL :: MySQL 8.0 Reference Manual :: 13.3.8.2 XA Transaction States](https://dev.mysql.com/doc/refman/8.0/en/xa-states.html))

XA 事务在 InnoDB 引擎中可用。MySQL XA 事务实现基于 X/Open CAE 文档 《Distributed Transaction Processing: The XA Specification》。这份文档由 *Open Group* 发布，可以在 http://www.opengroup.org/public/pubs/catalog/c193.htm 访问。当前 XA 实现的局限可以在 [Section 13.3.8.3, “Restrictions on XA Transactions”](https://dev.mysql.com/doc/refman/8.0/en/xa-restrictions.html) 查看。

...

XA 事务是全局事务关联的一组事务性动作，要么全部成功，要么全部回滚。本质上，这是让 ACID 属性“提升了一层”，让多个ACID事务可以作为一个全局操作的一部分执行，使得这个全局操作也具备ACID属性。（对于非分布式事务，应用如果对读敏感，则`SERIALIZABLE`更推荐。`REPEATABLE READ` 在分布式事务中并不是很有效。）

#### 事务模型

![DTM](image/MySQL-XA-and-2PC-DTP-model/事务模型.webp)

其中：

- **AP：**用户程序
- **RMs：**数据库
- **TM：**事务管理器

用户程序不用介绍。

根据 Open Group 在 Distributed Transaction Processing Model 中的定义，一个典型的 RM 可以是一个支持事务的数据库（DBMS）。

TM 则是协调整个二阶段提交过程的中介。AP从TM获得XID，完成 `XA START` 到 `XA END` ，然后告知 TM 就绪。TM提取本次事务的所有XID，向RMs发出`XA PREPARE`请求，如果失败则对每个 XID 发出 `XA ROLLBACK` ，成功则继续发出 `XA COMMIT` 。

需注意的是，`XA PREPARE` 失败可以通知其他事务回滚，但`XA COMMIT` 失败则只能等待数据库恢复，再行重试。`XA PREPARE`一旦成功，则`XA COMMIT` 一定成功（或者说必须成功）。

TM 实现要求自身崩溃后必须能清理恢复，防止出现XA事务死锁。

- 继续 PREPARE 需要提交的事务
- 继续 ROLLBACK 未完成 ROLLBACK 的事务
- 继续 COMMIT 未能 COMMIT 的事务
  - 未能 COMMIT 成功则需要重试直到成功

几个 TM 角色（或整套方案）的实现：

- [seata/seata: Seata is an easy-to-use, high-performance, open source distributed transaction solution. (github.com)](https://github.com/seata/seata/)
- [UPSQL Proxy-技术产品- 中国银联开放平台 (unionpay.com)](https://open.unionpay.com/tjweb/product/detail?proId=43)
- [分布式数据库TDSQL MySQL版_企业级分布式数据库解决方案 - 腾讯云 (tencent.com)](https://cloud.tencent.com/product/dcdb/)

#### 基本用法

```mysql
XA {START|BEGIN} xid [JOIN|RESUME]

XA END xid [SUSPEND [FOR MIGRATE]]

XA PREPARE xid

XA COMMIT xid [ONE PHASE]

XA ROLLBACK xid

XA RECOVER [CONVERT XID]
```

其中 `XA START` 后跟随的 `JOIN`和`RESUME`子句没有任何效果。

`XA END` 后跟随的 `SUSPEND` 和 `FOR MIGRATE` 子句也没有任何效果。

任何`XA`语句都以`XA`关键字开头，大多`XA`语句都需要`xid`值。`xid` 是 **XA事务的标识符** ，它确定语句应用到哪个XA事务上。

`xid`值可以由客户端指定或 MySQL 服务器生成。

一个`xid`值有一到三个部分：

```
xid: gtrid [, bqual [, formatID ]]
```

`gtrid` 是**全局事务标识符** ，`bqual` 是**分支修饰符**，`formatID`是一个标记 `gtrid` 和 `bqual` 格式的数字。

`gtrid` 和 `bqual` 必须是字符串字面量，最多不超过 64 **字节** 长。`gtrid` 和 `bqual` 可以以多种方式指定，可以用引号包围的字符串（`'ab'`）；十六进制字符串（`X'6162'`，`0x6162`）；或者二进制值（`b'nnn'`）。

`formatID` 必须是一个无符号整数。

`gtrid` 和 `bqual` 值在 MySQL 服务器的底层 XA 支持程序中被解释为字节。不过，服务器在解释包含XA语句的SQL时，可能设置了特定字符集。安全起见，最好将 `gtrid` 和 `bqual` 写作十六进制字符串形式。

`xid` 值通常是由事务管理器生成。一个事务管理器产生的`xid`必须与另一个事务管理器产生的`xid`不同。一个给定的事务管理器必须能在 `XA RECOVER` 返回的 `xid` 列表中识别出属于自己的 `xid` 。

`XA START xid` 以指定的 `xid` 开启一个新 XA 事务。每个 XA 事务必须包含一个唯一的 `xid` ，`xid` 不能正在被另一个 XA 事务使用。唯一性通过 `gtrid` 与 `bqual` 评估。该 XA 事务的后续 XA 语句都必须指定`XA START`中指定的 `xid`。如果使用XA语句但没有指定一个对应XA事务的`xid`，则产生一个错误。

多个XA事务可以是同一个全局事务的组成部分。在同一个全局事务中所有XA事务的`xid`必须使用同一个 `gtrid` 值。因此，`gtrid` 必须全局唯一以避免混淆。全局事务中XA事务`xid` 的 `bqual` 部分必须互不相同。（要求 `bqual` 不同是当前MySQL实现的限制，并不是XA规范的一部分。）

`XA RECOVER` 语句返回 MySQL 服务器中处于 `PREPARED` 状态的 XA 事务信息。输出中每一行都是一个服务器上的 XA 事务，不论是哪个客户端启动的事务。

执行 `XA RECOVER` 需要 `XA_RECOVER_ADMIN` 特权。这个特权需求是为了防止用户发现其他不属于自己的事务`xid`，不影响XA事务的正常提交和回滚。

`XA RECOVER` 输出类似下面这样

```mysql
mysql> XA RECOVER;
+----------+--------------+--------------+--------+
| formatID | gtrid_length | bqual_length | data   |
+----------+--------------+--------------+--------+
|        7 |            3 |            3 | abcdef |
+----------+--------------+--------------+--------+
```

其中：

- `formatID` 是 `xid` 中的 `formatID` 部分
- `gtrid_length` 是 `xid` 中 `gtrid` 部分的长度（字节单位）
- `bqual_length` 是 `xid` 中 `bqual` 部分的长度（字节单位）

XID值可能包含不可打印的字符。`XA RECOVER` 允许一个可选的 `CONVERT XID` 子句，以便客户端可以请求十六进制格式的 XID 值。

#### 事务状态

一个 XA 事务经历以下状态

1. 使用`XA START`启动的XA事务，进入`ACTIVE`状态。
2. 一个处于`ACTIVE`状态的XA事务，可以发出SQL语句填充事务，然后发出`XA END`语句。`XA END`语句令XA事务进入`IDLE`状态。
3. 一个处于`IDLE`状态的XA事务，可以发出`XA PREPARE`语句或`XA COMMIT ... ONE PHASE`语句。
   - `XA PREPARE` 语句令XA事务进入`PREPARED` 状态。`XA RECOVER` 语句此时可以发现并列出此事务的 XID。`XA RECOVER` 可以列出所有处于 `PREPARED` 状态的 XA 事务的 XID。
   - `XA COMMIT ... ONE PHASE` 准备并提交XA事务。`xid`不会列出在`XA RECOVER`中，因为XA事务实际在执行语句后就结束了。
4. 一个处于`PREPARED`状态的XA事务，可以发出`XA COMMIT`语句来提交并结束XA事务，或发出`XA ROLLBACK`来回滚并结束事务。

![image-20210831105435330](image/MySQL-XA-and-2PC-DTP-model/xa-state-transition-diagram.png)

下面是一个简单的XA事务例子，作为一个全局事务，插入一个行。

```mysql
mysql> XA START 'xatest';
Query OK, 0 rows affected (0.00 sec)

mysql> INSERT INTO mytable (i) VALUES(10);
Query OK, 1 row affected (0.04 sec)

mysql> XA END 'xatest';
Query OK, 0 rows affected (0.00 sec)

mysql> XA PREPARE 'xatest';
Query OK, 0 rows affected (0.00 sec)

mysql> XA COMMIT 'xatest';
Query OK, 0 rows affected (0.00 sec)
```

在给定客户端连接的上下文中，XA事务和本地事务彼此互斥。举例来说，如果`XA START`发出并启动了一个XA事务，此时不能再启动一个本地事务直到XA事务被提交或回滚。反过来说，如果一个本地事务已经通过`START TRANSACTION`启动，则不能执行任何XA语句直到本地事务被提交或回滚。

如果一个XA事务在`ACTIVE`状态，则不能发出任何产生隐式提交的语句（如 `create table`），因为这违反了XA协议，导致不能回滚XA事务。尝试执行这类语句会导致一个错误：

```
ERROR 1399 (XAE07): XAER_RMFAIL: The command cannot be executed
when global transaction is in the ACTIVE state
```

#### XA 事务实验

准备数据库

```mysql
create database if not exists test;
create table if not exists test123 (
  `id` bigint primary key auto_increment,
  `name` varchar(64) not null
);
```

启动一个 XA 事务，插入表，最后提交。

```mysql
xa start 'this-is-gtrid','this-is-bqual';
insert into test123(name) values('distributed transaction!');
xa end 'this-is-gtrid','this-is-bqual';

-- 准备
xa prepare 'this-is-gtrid','this-is-bqual';

-- 应该看到上一步 prepare 的 xa 事务
xa recover;

-- 提交 xa 事务。
xa commit 'this-is-gtrid','this-is-bqual';
-- 或者 rollback
-- xa rollback 'this-is-gtrid','this-is-bqual';
```

执行完成后，可以发现表中多了一条记录

```mysql
select * from test123;
```



