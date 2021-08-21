---
title: MySQL 24小时入门笔记 - 4
tags:
  - mysql
date: 2018-06-23 22:34:00
categories:
  - mysql
---

## 创建表

### CREATE TABLE

`CREATE TABLE`的作用是创建表。不多说，先创建个简单的学生表。

```SQL
CREATE TABLE students (
	id int,
    name char(16) NOT NULL,
    primary key (id)
);
```

这里没写 `ENGINE=InnoDB`，因为这是新 MariaDB 的默认值。

那么进入正题，`CREATE TABLE`的语法如下。

```SQL
CREATE TABLE [表名] (
	[列名] [类型] [约束和其他属性],
    [列名] [类型] [约束和其他属性],
    ....
    [其他表配置]
);
```

很容易看出，括号里面写的是表的相关配置，包括列定义，主键定义，索引定义等等。

### 默认值

在创建表时可以指定默认值，有默认值的列在插入时可以不填。

语法如下。

```SQL
CREATE TABLE [表] (
	[列] [类型] DEFAULT [值],
);
```

即可为一个列设定默认值。

### 非空

非空约束非常常见。比如说，我们要记录学生信息，包括学号、成绩、姓名，那么学生姓名能不能留空呢？显然不行，因为没有姓名的记录让谁看都是一脸懵逼，这破坏了一条记录的完整性。

创建非空约束的语法如下。

```SQL
CREATE TABLE [表] (
	[列] [类型] NOT NULL,
);
```

这就创建了非空约束。非空约束下，插入数据时不能不填写这个列。

如果需要要求可空，那么这样做。但一般不用特地写，很多`DBMS`的列默认创建就是可空的。

```SQL
CREATE TABLE [表] (
	[列] [类型] NULL,
);
```

## 修改表

### ALTER TABLE

`ALTER TABLE`可以修改表定义，添加删除列，修改约束，等等。

### 添加列

举例，在一个只有学号和姓名两个列的学生表加入一个新的成绩列，代码如下。

```SQL
ALTER TABLE students
ADD score int;
```

语法基本是这样。

```SQL
ALTER TABLE [表名]
ADD [列名] [类型] [其他属性和约束];
```

后面列的定义写法基本和`CREATE TABLE`时差不多。

### 删除列

和添加列差不多，但删除的关键字**不是**`DELETE`，而是`DROP`。

```SQL
ALTER TABLE [表名]
DROP [列名];
```

### 添加外键约束

外键约束其实保证的是**引用完整性**，外键约束的列的值必须引用了一个有效的行，或者是`NULL`。

举例来说，我们先有两个表。

学生表

| id  | name      | class |
| --- | --------- | ----- |
| 1   | student 1 | 1     |
| 2   | student 2 | 2     |
| 3   | student 3 | 3     |

班级表

| id  | level |
| --- | ----- |
| 1   | Lv5   |
| 2   | Lv4   |
| 3   | Lv3   |

为了让学生表的`class`关联到班级表的`id`，我们要这样做。

```SQL
ALTER TABLE students
ADD CONSTRAINT fk_students_classes
FOREIGN KEY (class) REFERENCES classes (id);
```

语法基本是这样子的

```SQL
ALTER TABLE [保存外键的表]
ADD CONSTRAINT [外键约束的名字，一般fk开头]
FOREIGN KEY ([外键名]) REFERENCES [引用的表名] ([引用的键名])
```

比较复杂。

### 删除表

那么终于到了期待已久的删库跑路阶段。

删除表的语法非常简单，那么从一开始活到现在的这所学校终于干不下去了，校长决定遣散学生。

```SQL
DROP TABLE students;
```

人走光了。

### 重命名表

校长决定把学校改成夜总会，于是他写道：

```SQL
RENAME TABLE school TO night_club;
```

要是换行有这么容易就好了......（你敢说回车看看）
