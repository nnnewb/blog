---
title: 储存过程、函数和触发器
slug: stored-procedure-function-and-triggers
date: 2022-06-16 10:34:59
categories:
- mysql
tags:
- mysql
---

## 前言

工作里很少用到这些功能，备考数据库系统的时候发现这几个不是考点的地方确实还得现查文档才能写。

因为不考又不怎么用，所以本篇只是简短地记一下储存过程、函数和触发器写法，没深度，也不适用于做备考资料。仅仅是给自己扫盲。

## 储存过程

### 是什么？

这是个很容易引起误解的名字，英文是 *Stored Procedure*，也就是被储存的（Stored）过程（Procedure）。一翻译感觉像是说储存这个动作的过程一样。

### 什么时候用？

参考一个爆栈的回答 [MySQL stored procedures use them or not to use them](https://stackoverflow.com/questions/6368985/mysql-stored-procedures-use-them-or-not-to-use-them) ，储存过程本身不像一般的编程语言中所谓的过程，它有很多缺陷。

1. 不可移植。这意味着可能出现 *vendor lock-in* 的风险。
2. 难以测试、更新、维护，缺乏支持，没有日志、跟踪、调试信息。甚至很难和 VCS 工具打配合。
3. 不容易和其他技术整合。
4. 参考文档，发现在开启binlog时创建储存过程还需要高特权。

而储存过程常被鼓吹的优势：高性能，就是个谜。老话说提前优化是万恶之源，储存过程的“高性能”本身也不是免费午餐，除非真的 **真的** 需要，非它不可，没有替代方案，而且充分考虑过开发、管理、维护储存过程带来的额外复杂性，再选择用储存过程也不迟。

### 怎么用？

定义储存过程的语法

```sql
-- CREATE PROCEDURE <proc>([parameters[, ...]])
CREATE PROCEDURE proc(uid INT)
BEGIN
-- PROCEDURE BODY
-- ordinary SQL query
UPDATE customer SET goodie=1 WHERE cuid=uid;
END
```

对，储存过程没有返回值。所以必要的时候可以用关键字`IN`和`OUT`修饰参数，来传递变量。类似 C# 的 `out`、`ref` 关键字。微软文档也喜欢在函数签名里加 `IN` 或 `OUT` 的宏来标识参数会不会被覆写。不过其他编程语言里就少见了，更提倡用返回值显式传递。

```sql
CREATE PROCEDURE proc(IN uid INT, OUT goodie INT)
BEGIN
SELECT goodie INTO goodie FROM customer WHERE cuid=uid;
END

CALL proc(@goodie);
SELECT @goodie;

DROP PROCEDURE IF EXISTS proc;
```

在`BEGIN`前面还可以加一些修饰，比如`COMMENT`。常见的是`DETERMINISTIC`，这个关键字表示过程输出是稳定的，对同一个参数总是输出同样的结果，对数据库内部优化查询有用，大概。默认是`NOT DETERMINISTIC`。

## 函数

### 是什么？

类似储存过程，但有返回值。

### 什么时候用？

问题和储存过程类似，不再赘述。

### 怎么用？

```sql
CREATE FUNCTION func([IN|OUT] param type)
RETURNS type
BEGIN
body
END

SELECT func(cuid) FROM customers;

DROP FUNCTION IF EXISTS func;
```

创建语法和储存过程类似，使用时不需要 `CALL`，而是和普通 SQL 函数一样。

## 触发器

### 是什么？

触发器是一个和表关联的数据库对象，在特定事件发生时激活。不能在临时表（使用`TEMPORARY`关键字的`CREATE TABLE`语句创建的表）上创建触发器。

### 什么时候用？

如果按数据库系统原理这门课上的考点来说，触发器可以帮助保持数据完整性。但现实世界很少有这么干的，除了上面提到的储存过程和函数都存在的缺陷之外，设计不好的触发器也可能造成性能问题。

所以老样子，除非真的非它不可，不然敬而远之就是了。

### 怎么用？

```sql
CREATE TRIGGER trigger_name
{BEFORE|AFTER} {INSERT|UPDATE|DELETE} ON tbl_name
FOR EACH ROW
[{FOLLOWS|PRECEDES} other_trigger_name]
body
```

一个考点是触发器只能对DML中增删改事件做出反应。

## 总结

水了将近1000字。

SQL知识里一块空白给填上了，强迫症一本满足。