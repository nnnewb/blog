---
title: MySQL 24小时入门笔记 - 2
tags:
  - mysql
date: 2018-06-23 15:41:00
categories:
  - mysql
---

## 查询

### SELECT

`SELECT`是一个特殊的关键字，它的语义是查询，取出结果。

> **注意**：仅为个人理解。

### FROM

`FROM`子句，标识要查询的对象的来源，来源可能是多个的。在查询有多个来源表的情况下，称之为联结查询（`Join query`）。

最常见的常规写法是`SELECT column FROM table`，表示从特定表取出所有行的特定列。

### WHERE

`WHERE`子句用于过滤查询的行，只有满足条件的行会被查询出来。

常见的用法有`SELECT column FROM table WHERE column <> 0`，表示在`table`表中查询`column`非空的行，返回这些行的`column`。

其中的二元关系运算符`<>`表示不等于，其他常见的关系运算符还有这些。

| 运算符 | 含义     |
| ------ | -------- |
| `=`    | 相等     |
| `>`    | 大于     |
| `<`    | 小于     |
| `>=`   | 大于等于 |
| `<=`   | 小于等于 |
| `!=`   | 不等于   |
| `<>`   | 不等于   |

此外还有一些`SQL`关键字可以辅助编写判断逻辑。

`SQL`关键字`IN`可以用于判断元素是否在集合中。举例，`SELECT 1 IN (1,2,3)`，查询`1`是否在`1,2,3`这个集合中。被判断的集合需要被小括号包围，并且以逗号分隔元素。

`SQL`关键字`BETWEEN`可以判断元素是否在一定区间中。举例，`SELECT 1 BETWEEN 0 and 10`，查询`1`是否在`0`到`10`的区间内。语法是`BETWEEN [low] AND [high]`，区间较小的一端必须在左侧，较大的一端必须在右侧。

`SQL`关键字`LIKE`可以用非常简单的通配符来判断元素是否匹配一定的规则。举例，`SELECT 'abcabcabc' LIKE '%CAB%'`，判断字符串`abcabcabc`是否匹配`%CAB%`。值得注意的是，模式串中的`%`代表的是匹配 0 或任意多个字符，就像是正则表达式中的`*`一样。此外还有`_`，下划线，匹配 1 个任意字符。

`MySQL`扩展的`REGEXP`可以用正则表达式来匹配元素是否符合模式串。举例，`SELECT 'abcabcabc' REGEXP '.*cab.*'`，正则表达式不做赘述，简单的模式串大家都会写。

### ORDER BY

`ORDER BY`就像字面意义上说的那样，按照某个列来进行排序。举例来说，我有一个学生表，记录了学号和姓名，我可以按照学号排序。

```SQL
SELECT * FROM students ORDER BY id;
```

默认排序是升序，也可以通过指定`DESC`或者`ASC`来决定怎么排。`ASC`是升序，`DESC`是降序。

```SQL
SELECT * FROM students ORDER BY id DESC;
```

### AS

`AS`常见的用法是建立别名。

```SQL
SELECT column AS id_alias FROM my_table AS table_alias WHERE table_alias.column <> 1;
```

这里出现了一个新的语法细节，`table_alias.column`。用点`.`连接表名和列名的行为类似于 C++中的

```C++
typedef table_alias = my_table;
auto id_alias = SELECT(table_alias::column, table_alias::column != 0);
```

看得出来，`table_alias.column`是完全限定了`column`是哪个`column`，之所以有这种语法，是因为`FROM`子句需要支持多个表作为查询来源。到时候可能就会用到`table1.column <> 1 AND table2.column <> 2`这样的写法了。

而查询开头的`column AS id_alias`则是标识查询结果列叫做`id_alias`，举例如子查询的情况下，便于引用。

### JOIN

`JOIN`的术语叫做**联结**，使用了`JOIN`关键字的查询叫做**联结查询**。

联结查询和一般的查询不同的地方是，联结查询的数据来源是多个表。

最简单的联结查询是内联结查询。

举例来说，我现在有表`students`如下，所有学生根据超能力开发等级分配到多个班级。

| id  | name | class |
| --- | ---- | ----- |
| 1   | stu1 | 1     |
| 2   | stu2 | 2     |
| 3   | stu3 | 3     |
| 4   | stu4 | 4     |

又有表`top_class`，收录了所有接收高等级超能力者的班级，能进入这些班级的学生都是如同能考上`985`、`211`般恐怖如斯的存在。

| id  | name |
| --- | ---- |
| 1   | Lv 5 |
| 2   | Lv 4 |
| 3   | Lv 3 |

现在我们要查询出学生中那些恐怖如斯的存在有哪些。

```SQL
SELECT students.name AS name FROM students INNER JOIN top_class ON top_class.id = students.class;
```

语法`JOIN [表] ON [条件]`也很简单啦。在例子中，`JOIN`表示要联结表`top_class`，`ON`表示查询的对象要符合条件`top_class.id = students.class`。不好理解？看看伪代码。

```C++
for(auto student : students) { // 先过滤 students 表本身，这个过滤应该由 WHERE 子句完成
  for(auto cls : top_class) { // 然后联结表 top_class
    if(student.cls = cls.id) // 判断 ON students.class = top_class.id
      results.push(student); // 得出结果
  }
}
```

> 注意，伪代码的查询过程是错误的，为了方便理解 students.class = top_class.id 才这么写。真实数据库实现联结查询的方法应当查阅对应`DBMS`的文档。

注意的关键点有`ON`很像但不同于`WHERE`，在了解`LEFT JOIN`和`RIGHT JOIN`时会区分。

### LEFT JOIN

`LEFT JOIN`又叫**左联结**，基本思路是写在`LEFT JOIN`左边的表满足条件即可作为结果，即使右边的表没有满足条件的条目。

还是以上文的学园都市数据库为例（我 tm 写了什么...）

学生表 `students`

| id  | name | class |
| --- | ---- | ----- |
| 1   | stu1 | 1     |
| 2   | stu2 | 2     |
| 3   | stu3 | 3     |
| 4   | stu4 | 4     |

班级表 `top_class`

| id  | name |
| --- | ---- |
| 1   | Lv 5 |
| 2   | Lv 4 |
| 3   | Lv 3 |

现在我们查询学生都处在哪些班级，得到班级的名字。

```SQL
SELECT students.name as name, top_class.name as cls
       FROM students LEFT JOIN top_class
            ON top_class.id = students.class;
```

查询结果应该是这样子的。

| name | cls    |
| ---- | ------ |
| stu1 | Lv 5   |
| stu2 | Lv 4   |
| stu3 | Lv 3   |
| stu4 | `NULL` |

注意到了吗？`stu4`虽然不是`top_class`的学生，但是还是被查询出来了。

### RIGHT JOIN

继续拿学园都市做例子......

其实是和左联结一个鸟样。

```SQL
SELECT students.name as name, top_class.name as cls
       FROM top_class RIGHT JOIN students
            ON top_class.id = students.class;
```

我们注意到......我就是把 `students`和 `top_class`换了个位置。查询结果其实是一样的。

| name | cls    |
| ---- | ------ |
| stu1 | Lv 5   |
| stu2 | Lv 4   |
| stu3 | Lv 3   |
| stu4 | `NULL` |

### CROSS JOIN

交叉联结，查询结果是联结的表和`FROM`的表的笛卡尔积，这么说听的明白不？听不明白就算了，因为交叉联结基本用不到。

其实就是把两个表的每个行都排列组合一下：

- 表 A 行 1-表 B 行 1
- 表 A 行 1-表 B 行 2
- ......
- 表 A 行 10-表 B 行 1
- 表 A 行 10-表 B 行 2
- 表 A 行 10-表 B 行 3
- ......

### JOIN 自己？

术语叫自联结，其实也挺好理解的，直接举个例子看看。

| id  | name | class |
| --- | ---- | ----- |
| 1   | stu1 | 1     |
| 2   | stu2 | 1     |
| 3   | stu3 | 2     |
| 4   | stu4 | 2     |

> 注意我数据改了哈。

现在要查询出所有和`stu1`同一个班级的学生。

一般我们想怎么查？先查出`stu1`是哪个班级的：`SELECT class FROM students WHERE name = 'stu1'`，然后查出所有属于这个班级的学生：`SELECT name FROM students WHERE class = [上次查出来的班级]`。

那么...怎么写成一句话呢？

这时候自联结就可以上场了。

```SQL
SELECT s1.id, s1.name, s1.class
FROM students AS s1 INNER JOIN students AS s2
WHERE s1.class = s2.class
	AND s2.name = 'stu1';
```

查询结果是

| id  | name | class |
| --- | ---- | ----- |
| 1   | stu1 | 1     |
| 2   | stu2 | 1     |

基本思路是这样的：`FROM`的表是`s1`，因此`INNER JOIN`查询结果来自`s1`而不是`s2`。查找`s1`表中每个行的`class`在`s2`表里有没有行具有同样的`class`属性，同时，`s2`具有和`s1`同样`class`属性的行还必须有个`stu1`的`name`。

分析得知，`s2`中有`stu1`这个`name`的行只有`1`，所以`s2`表其实长这样。

| id  | name | class |
| --- | ---- | ----- |
| 1   | stu1 | 1     |

这时候再去看`s1`表，`s1`表的`class`同时存在于`s2`表的行只有`1`和`2`了。

### OUTER JOIN

其实`OUTER JOIN`上面的`LEFT JOIN`和`RIGHT JOIN`已经讲过了，`LEFT JOIN`的完整写法就是`LEFT OUTER JOIN`，`RIGHT JOIN`就是`RIGHT OUTER JOIN`，和`INNER JOIN`的区别在于`OUTER JOIN`包含了指定表里不满足`ON`条件的行。

这有个知识点，就是`ON`条件不过滤指定`OUTER JOIN`的表的不满足条件的行，但是`WHERE`会过滤。

### UNION

`UNION`关键字的术语是**联合查询**。

作用是将多个`SELECT`的结果放在一起并返回。

举个例子......我们要查询全美最好的大学`american_top_college`和中国最好的大学`chinese_top_college`数据，来决定报考哪个大学（反正都考不上），如果不想写成两句`SELECT`，然后手工合并成一个表格的话，那么就用`UNION`查询吧。

```SQL
SELECT 'american' AS nation, american_top_college.name AS college_name, american_top_college.score_line AS score_line
FROM american_top_college
UNION
SELECT 'china' AS nation, chinese_top_college.name AS college_name, chinese_top_college.score_line AS score_line;
```

查询结果...不展示了。

还有个细节可能要注意，如果有大学同时是美国大学和中国大学的话，那么为了在联合查询中排除相同的项目，可以使用`UNION ALL`而不是`UNION`。

### FULLTEXT

`MySQL`支持一种实用的文本索引方式，叫做**全文本搜索**。大家都知道，正则表达式和简单通配符来查找文本是非常消耗性能的操作，而且难以优化（反正我想不出任何减少查询的优化思路）。`MySQL`提供了全文本搜索的属性来帮助索引文本（但是想到中文支持我觉得已经凉的差不多了），快速查询出包含特定词汇之类的行。

> 抱歉我觉得不行。不说别的，中文分词就......

跳过了跳过了。
