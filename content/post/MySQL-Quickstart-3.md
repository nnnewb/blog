---
title: MySQL 24小时入门笔记 - 3
tags:
  - mysql
date: 2018-06-23 21:51:00
categories:
  - sql
---

## 插入

### INSERT

`INSERT`用法非常简单。现在我们有表`students`如下。

| 列名 | 类型     | 约束        |
| ---- | -------- | ----------- |
| id   | int      | primary key |
| name | char(16) | NOT NULL    |

向里面插入一条学号为`1`，姓名为`学姐`的学生，只需要写如下`SQL`语句。

```SQL
INSERT INTO students VALUES (1, '学姐');
```

语法

```SQL
INSERT INTO [表] VALUES (列值1,列值2,...);
```

其中`INSERT`语句有一个简单的变体，能比较明确地指明将值交付给哪个列。

```SQL
INSERT INTO students (id, name) VALUES (1, '学妹');
```

这样写相当于指明了`1`应该是`id`，`'学妹'`应该是`name`。

插入多条也很简单，只要在`VALUES`后面跟更多小括号包围的值集合就行了，记得拿括号分隔，下面给个例子。

```SQL
INSERT INTO students (id, name)
VALUES (1, '学渣'), (2, '学霸'), (3, '学神');
```

### INSERT SELECT

这个写法比较有意思，从一个表查询出数据，并插入另一个表。

举个例子来说，我们有两个班级表，分别叫`学渣班`和`补习班`，一旦学渣成绩烂到一定程度，那么我们就要把他分配到补习班里去强制补习。

怎么做呢？看下面啦。

```SQL
INSERT INTO 补习班(name,score)
	SELECT 学渣班.name, 学渣班.score
    FROM 学渣班
    	WHERE 学渣班.score < 10;
```

值得注意的是，`INSERT` 填充补习班表时用的并不是你`SELECT`的列名，而是`SELECT`后列名的顺序，来对应到要`INSERT`的表的列上。

其他的写法和`SELECT`相同。

## 修改

### UPDATE

`UPDATE`语句的作用是修改现存行的数据，非常值得注意的是用`UPDATE`语句时一定要小心写`WHERE`子句，不然就等着删库跑路吧。

依然举个实际栗子，学号为`10`的学生成绩由于作弊而被取消了，我们要更新他的成绩为 0 分，这真是个悲伤的故事:P

```SQL
UPDATE students SET score = 0 WHERE id = 10;
```

语法是这样的。

```SQL
UPDATE [表名] SET [列名] = [新值] WHERE [条件];
```

更新多条的话是这样的

```SQL
UPDATE [表名]
SET [列1] = [新值],
    [列2] = [新值],
    ...
    [列N] = [新值]
WHERE [条件];
```

> 千万小心，如果没有 `WHERE`子句的话，指定的列会全部被设置成这个值。这样一来，所有的学生都变成了 0 分......你会被手撕了的。

## 删除

### DELETE

`DELETE`的作用是删除行，同样的，万分注意`WHERE`子句一定要正确编写，不然真的要删库跑路了。

同样以之前那位作弊的同学为例，很遗憾，他又一次作弊被抓住了，传说中的高科技 AR 技术作弊眼镜也没能让他逃过监考员的火眼金睛，于是他被退学了......

另一个悲伤的故事:P

```SQL
DELETE FROM students WHERE id = 10;
```

语法是这样子的。

```SQL
DELETE FROM [表名] WHERE [条件];
```

如果不写`WHERE`的话......找个好点的新工作吧，不要再去写`SQL`了，ORM 多好。

> 注意，不写`WHERE`子句会删除这个表里的所有行。
