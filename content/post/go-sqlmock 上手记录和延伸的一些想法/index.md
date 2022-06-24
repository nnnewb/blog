---
title: go-sqlmock 上手记录和延伸的一些想法
date: 2022-06-24 14:38:00
categories:
- golang
tags:
- golang
- go-sqlmock
- mock
- 单元测试
- 测试
---

## 前言

用 `DATA-DOG/go-sqlmock` 结合 gorm 的简单案例和一些延伸想法。

## 为什么mock

使用 mock 技术的主要原因就是确保待测代码的行为稳定，不会因为外部条件变化而造成测试结果不稳定。比如网络延迟或断开、数据库高负载或维护中、你需要的微服务正在被另一个人调试或者你不在内网但急需排查个问题等等。

开发中这些问题都还好，因为偶发原因失败就失败，排除后测通就行。但一旦单测进入自动化运行的阶段，这些问题就会变得很烦人：测一个服务要启动一整个集群；写用例的时候要考虑支持并发测试提高单测速度；各种偶发故障/平台故障/环境问题/配置错误频繁打断工作流......

实际体验过亲手写微服务 API 单测然后放 CI 跑这会儿该都是泪。

## 构造 GORM.DB

```go
db, mock, err = sqlmock.New()
if err != nil {
    return err
}

gormDB, err = gorm.Open(postgres.New(postgres.Config{Conn: db}))
if err != nil {
    return err
}
```

`gorm.Open`的首参数 `Dialector`是具体数据库驱动，同时也指定了使用的 SQL 方言。`go-sqlmock`只提供了`*sql.DB`，所以还需要 `Dialector` 构造方法支持从 `sql.DB` 创建。常用的数据库大概都支持。

## 控制反转

非常重要的一步，待测代码不能硬编码了数据库实例，不然就没有 mock 的空间了。放 python 里说不定还能 monkeypatch 弥补下，go 里就全看代码架构设计好不好。

go 的设计理念之一就是 *Composition over inheritance* ，不仅体现在类型系统设计上，在组织代码时的体现就是优先用显式装配的方式构造对象，避免使用全局变量等强耦合方式。

再做一句补充，什么叫强耦合？如果你发现待测功能有一个依赖项没法单测的时候 mock 掉，那多半就是写法强耦合了。

所以用 mock 写单测还有个好处，就是发现待测代码里不好的设计。当然前提还是单测设计得好的情况下，不管做什么事想搞砸总比想做好容易。

回到正题，虽然这一小节说 IoC ，但并不是要求用什么 DI 框架，而是指优先用装配的方式显式提供依赖或依赖的工厂函数，避免在待测代码内自行构造依赖对象或引用全局变量。

```go
type B interface { /* ... */ }
type BImpl struct { /* ... */ }

type A struct {
    b *B
}

func NewA(b *B) *A {
    return &A{
        b: b,
    }
}

func (*A) method() {
    NewBImpl().Say() // 强耦合，想再把 B 换成别的东西必须侵入 A 的业务，无法 mock
}

func (a *A) method2() {
    a.b.Say() // 弱耦合，可以随便把 b 换成别的类型，单测这个接口时 b 可以替换
}
```

这种耦合关系还得具体分析，像是业务代码里直接用 `gorm.DB` 做函数签名，的确对 GORM 形成了强耦合，但 GORM 内部和 `gorm.Dialect` 又是弱耦合，`gorm.Dialect` 和 `sql.DB` 强耦合，`sql.DB` 和驱动弱耦合。

于是我们可以选择 mock `gorm.Dialect` 或 mock 驱动，实际分析来看，`gorm.Dialect` 大多可以从 `sql.DB` 构造，mock 掉 `sql.DB` 就等于 mock 掉了 `gorm.Dialect`，等于 mock 掉了 `gorm.DB`，所以 mock `sql.DB` 收益更好。当然，mock `sql.DB` 的底层实现还是 mock 驱动。

和 `gorm` 构成强耦合不是特别严重的问题（不太可能随便更换 ORM 框架），但能把数据库操作单独抽象出来肯定是更好的，一方面可以单独单测，另一方面出现破坏性变更比如大版本升级时影响范围会更可控，变更结果也可以被已经写好的单测验证。

## 例子

```go
package tests

import (
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func TestMockGORM(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}

	gormDB, err = gorm.Open(postgres.New(postgres.Config{Conn: db}))
	if err != nil {
		t.Fatal(err)
	}

	mock.ExpectQuery(`SELECT "id" FROM "tbl"`).WillReturnRows(mock.NewRows([]string{"id"}).AddRow(1))
	results := make([]int, 0)
	gormDB.Table("tbl").Pluck("id", &results)

	if len(results) != 1 {
		t.Fatal("应该只有1行结果")
	}

	if results[0] != 1 {
		t.Fatal("结果应该是1")
	}
}

```

go-sqlmock 也不是完美的，mock 驱动的方案比较烦心的问题就是需要针对每个查询请求添加 `ExpectQuery`，为了模拟真实环境，还需要`WillReturnRows`添加返回结果。对于`SELECT * FROM tbl` 的情况就需要手写一遍字段名和模拟数据，相当啰嗦。可以考虑自己写个助手函数从 gorm 模型生成`sqlmock.Rows`。

## 结论

用 mock 技术写单测成本比较高，收益是单测跑起来稳定不容易意外挂，能并发测试，特别适合自动化跑，测试粒度也更细。

反之测 API 的话写起来成本比较低，但依赖一整套配套的运行环境（这一成本在系统规模很大或需要自动化频繁跑的时候会很明显），依赖的外部因素比较多容易意外挂，测试粒度比较粗。适合开发阶段写一个，或者大可用 `grpcurl` 或 `postman` 一类工具替代。

以上。
