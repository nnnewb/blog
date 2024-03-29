---
title: MySQL 24小时入门笔记 - 1
tags:
  - mysql
categories:
  - sql
date: 2018-06-23 02:24:00
---

## 1. 数据库概念

### 1.1 数据和储存

数据库本质上做的工作是储存和查询数据。理论上而言，`MySQL`应该叫做`DBMS`，也就是**数据库管理系统**，而不是**数据库**。

`DBMS`提供了统一的建立、使用、管理数据库的接口，常见的`DBMS`有`postgreSQL`、`MariaDB`、`SQL Server`等。

### 1.2 数据库和`Schema`

通常来说，一个`DBMS`会支持多个数据库共存。这里所说的*数据库*指的是特定数据库管理系统管理下的*数据库*，而不是上一节说的`DBMS`。

而`Schema`的中译术语一般叫**模式**，`Schema`描述了数据库的结构，比如说有哪些表，表有哪些字段，字段分别有哪些限制，有哪些声明了的函数，等等。

通常的`DBMS`往往是这样的结构：位于`DBMS`管理最顶层的是一个或多个数据库，数据库里存放表，表里以行为单位存放数据。

### 1.3 表、列、键、行

#### 1.3.1 表

表的英语术语是`Table`。

用过 Excl 吗？

| id  | name |
| --- | ---- |
| 1   | Mike |
| 2   | John |

直观的表就是一个二维的“表”，有行，有列。

#### 1.3.2 列

列的术语是 `Column`。

每个列都应该有一个特定的类型（`type`），使该列仅仅储存指定类型的数据。

#### 1.3.3 键......或者叫码

键的术语是 `Key`。

通常指的是`Primary Key`，也就是主键。主键可以是任意一个列。但是如果列是主键，那么这个列必须每个行都保证不和其他行重复。

主键也可以是多个列，如果是多个列，那么必须保证这些列的组合不重复。

举例来说

| db  | table | id  | name |
| --- | ----- | --- | ---- |
| aa  | aaaaa | 11  | xxxx |
| aa  | bbbbb | 11  | xxxx |

其中`db`和`table`还有`id`都是主键，只要保证没有两个行同时存在相同的`db`/`table`/`id`就算是满足了主键约束。

> 需要注意的是，多主键的可移植性存疑，不一定其他的`DBMS`会支持。

#### 1.3.4 行

行的术语是 `Row`。

每个行都是一条记录（`record`），换做对象的概念的话，也可以说，每个表都储存了一个其特有的的`Row`对象的集合，`Column`一一对应`Row`对象的属性。

比如上文的

| id  | name |
| --- | ---- |
| 1   | Mike |
| 2   | John |

对象概念表达就是

```C++
class row {
  int id;
  std::string name;
};

const std::set<row> table;
```

## 1.4 SQL 是什么

`SQL`的直译是**结构化查询语言**，其实就是标准化的数据库查询语言，基本每个`DBMS`都支持。

但是......数据库管理系统对`SQL`标准的支持并不是那么上心。其中有性能优化、平台优化之类的原因，也有数据库软件开发商自身的考虑。但总而言之，不要太期待同样的`SQL`能在任意`DBMS`里都一样跑得欢。
