---
title: go 的 defer 语句
date: 2021-01-05 10:01:48
categories:
  - golang
tags:
  - golang
references:
  - title: Effective Go - defer
    url: https://golang.org/doc/effective_go.html#defer
  - title: stackoverflow - Golang defer clarification
    url: https://stackoverflow.com/questions/28893586/golang-defer-clarification/28894103#28894103
---

昨天对项目做了个小重构，主要是对以前手写的 stmt.Close 没处理返回值的问题、还有各种该记录日志的地方没记日志等等，做了下处理。

老实说这事儿做着做着还有种奇妙的快感，类似于看高压水枪清污视频的感觉。哈哈，也亏领导不管事，代码也不 Review ，测试=摆设。

这不一上班就发现好多问题，幸好只推送到内网。

笑中带泪.gif

<!-- more -->

## 0x01 问题描述

问题倒是挺简单的，看下面的代码。

```go
stmt := db.Prepare(query)
defer SilentLogError(stmt.Close(), "stmt close failed")

row := stmt.QueryRow(params...)
defer row.Close()

if err = row.Scan(vars...); err != nil {
    return nil, err
}

return vars, nil
```

那么，请问上面的代码有什么问题呢？

标题都说了 defer 了，那问题肯定是出在 defer 这一行上。

## 0x02 defer 的求值

简单的结论就是: _defer f() 的参数在 defer 这一行求值_

具体到上面的例子，`defer f(i())` 这样的形式，可以先分成三个部分。

1. `defer` 本身的执行时机
2. `i()` 的求值时机
3. `f()` 的求值时机

把这三部分排一下序:

1. `i()`
2. `defer`
   > defer 把参数求值后包装成一个新函数延迟执行
3. `f()`

## 0x03 循环内 defer

循环内 defer 主要有两个问题

1. 可能产生造成巨量的 defer 函数，耗尽内存或拖垮执行速度
2. 在一些情况下会造成意料外的结果

看例子

```go
package main

import "fmt"

type Conn struct {
	ID int
}

func NewConn(id int) *Conn {
	return &Conn{ID: id}
}

func (c *Conn) Close() error {
	fmt.Printf("close %d!\n", c.ID)
	return nil
}

func main() {
	arr := make([]Conn, 5)
	for i := range arr {
		arr[i].ID = i
	}

	for _, conn := range arr {
		defer conn.Close()
	}
}
```

最终输出是

```
close 4!
close 4!
close 4!
close 4!
close 4!
```

造成这一结果的原因是接收器(receiver)也作为函数参数的一部分在 defer 时被求值。

`for _, conn := range arr` 这一行代码中，`conn` 本质是一个局部变量，其内存在循环期间可以视作固定的，而`func (c *Conn) Close() error` 接收器取了这个局部变量的地址：每一次循环，调用 Close 时，取得的都是同一个地址。最终导致 Close 的全部都是 conn 在函数结束时最后得到的值。

类似的，如果把接收器从指针改成值呢？接收器变成了值传递，将`conn`复制一次后保留作为 defer 函数执行时的参数，就会有正常的结果。

但并不是说循环内 defer **一定是** 不好的。

比如一个常见的场景，在循环里使用 SQL 查询。

```go
for query := queries {
    rows := db.Query(query)
    defer rows.Close()
}
```

可以明确知道 `rows` 是指针，而且 `rows.Close` 有指针接收器，就可以确定不会有问题。

## 0x04 defer 和闭包

```go
package main

import "fmt"

type Conn struct {
	ID int
}

func NewConn(id int) *Conn {
	return &Conn{ID: id}
}

func (c *Conn) Close() error {
	fmt.Printf("close %d!\n", c.ID)
	return nil
}

func main() {
	conn := &Conn{1}
	defer func() { conn.Close() }()
	conn = &Conn{2}
	defer func() { conn.Close() }()
}
```

和上面类似，这次输出是:

```
close 2!
close 2!
```

问题出现在 defer 后面这个画蛇添足的 `func(){}()` 上。众所周知 defer 会对参数求值，但闭包捕获的变量并不会。

因此，即使 `defer conn.Close()` 工作正常，但 defer `defer func() {conn.Close()}()` 就不一定了。两者在部分情况下并不能等价代换，除非你确信了解自己做了什么。

如果一定要用 `func(){}()` 的形式，那么 conn 只能通过参数形式传递给这个匿名函数。

```go
defer func(conn *Conn){
    _ = conn.Close()
}(conn)
```

对，说的就是烦人的*未处理的错误*警告。

## 0x05 Happy Hacking!

惯例，完。
