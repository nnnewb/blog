---
title: codegen 利器 go/types
slug: gotypes-for-codegen
date: 2022-04-11 13:00:00
categories:
- golang
tags:
- golang
- codegen
---

## 前言

本篇博客主要想介绍下 `go/types` 这个包。

目前关于 go 代码生成比较常见的是利用 `go/ast` ，结合 `text/template` 生成代码。这种生成方式显然是有局限性的：`go/ast` 这个包只能拿到语法树结构，但没有类型信息。比如 `var ctx context.Context` 可以解析成语法树节点 `ast.GenDecl`，但`context.Context` 只能解析出 `ast.SelectorExpr`，并不知道 `context.Context` 是一个 `struct`、`interface`还是`alias`。

在面对简单的代码生成时`go/ast`还能顶一下，但更复杂一点的需求，比如说根据 `struct` 生成 `thrift` 或者 `protobuf` 定义，`go/ast` 就有点吃力不讨好了。

## 入门

注意这块没照搬官方的 example，因为官方的 example 主要注重在怎么用 `go/types` 做类型检查，关注 `types.Config` 和 `types.Checker`，但我不是很想管 `checker` 怎么样，我们的目的是写个 codegen，想办法拿到更丰富的类型信息。

因此 `go/types` 的使用更关注的是其中的数据结构。

### 类型系统

先来个基本的例子。

```go
package main

import (
	"flag"
	"fmt"
	"go/importer"
	"go/token"
	"go/types"
	"log"
)

func main() {
	var pkgPath string
	var typ string
	flag.StringVar(&pkgPath, "package", "", "package path")
	flag.StringVar(&typ, "type", "", "type name")
	flag.Parse()
	if pkgPath == "" {
		println("-package is required")
		flag.Usage()
		return
	}
	if typ == "" {
		println("-type is required")
		flag.Usage()
		return
	}

	fst := token.NewFileSet()
	imp := importer.ForCompiler(fst, "source", nil)
	pkg, err := imp.Import(pkgPath)
	if err != nil {
		log.Fatal(err)
	}

	typename := pkg.Scope().Lookup(typ)
	if typename == nil {
		log.Fatalf("type %s not found", typ)
	}

	if named, ok := typename.Type().(*types.Named); ok {
		switch named.Underlying().(type) {
		case *types.Basic:
			println("primitive type")
		case *types.Interface:
			println("interface type")
		case *types.Struct:
			println("struct type")
		default:
			if named.Obj().IsAlias() {
				println("is alias type")
				return
			}
			fmt.Printf("%v", named)
		}
	}
}

```

很短，注意几个新出现的包和API：`go/importer`、`go/types`。

`go/importer`顾名思义是一个管理`import`功能的包，go 不是 python 这样解释执行或 Java 那样可以热加载代码的模型，`importer`基本是编译期才会用到。我们用`importer.ForCompiler`的目的是构造一个 `Importer`， **从源代码** 拿到类型信息。

从`Import`调用拿到一个 `*types.Package` 类型的返回值后，又使用 `Scope().Lookup()`从这个包作用域下查找指定的类型——这里提一嘴，`type xxx struct{}`这样的语句可以是块作用域的，`Scope().Lookup()`查找的是 **包内的全局类型定义** ，查找结果是一个 `types.Object`，可以理解成一个有类型的对象——比如全局 `var v int` 这样声明的 `v`。对于查找的是类型的情况，需要关注的就是 `.Type()`这个方法了。

顾名思义`.Type()`返回对象的类型，代码里的 type switch 应该很好地展示了整个过程。

另外还要注意到 `.(*types.Named)`，这里涉及一个 `named type`概念。所谓的 `Named` 在 [Go Specification 里是这样解释的](https://go.dev/ref/spec#Types)：

> **Predeclared types**, **defined types**, and **type parameters** are called *named types*. An alias denotes a named type if the type given in the alias declaration is a named type.

什么意思呢？`predeclared types` 指的是内置的类型，如 `int`、`byte`、`rune`，参考链接 [predeclares](https://go.dev/ref/spec#Predeclared_identifiers) 。而 `defined types` 指的是形如 `type Sample struct {}` 的类型定义，`type parameters` 则是 go 1.18 引入的泛型语法，例如 `type Sample[T any] struct {t T}` ，其中的`T`也是 `named type`。

那什么样的不是 `named type`呢？比如`type Sample = struct {}`，这里的 `Sample` 就不是 `named type`。注意前面引文的后半句：

> An alias denotes a named type if the type given in the alias declaration is a named type.

只有`named type`的别名才被视为`named type`，所以 `type Sample = int` 是 `named type`，但 `type Sample = struct{}` 或者 `type Sample = map[string]string` 都不是 `named type`。

好了，绕晕了就可以继续下一阶段了，开始了解 `Field` 和 `Method`。

### Field

我们稍微改一下上面的代码，在 `case *types.Struct` 下加入几行循环。记得 `switch`也改成`switch tp := named.Underlying().(type)`

```go
for i := 0; i < tp.NumFields(); i++ {
    field := tp.Field(i)
    fmt.Printf("field %s %v\n", field.Name(), field.Type())
}
```

又一个惯用法：`NumFields` 和 `Field`。注意`Field`拿到的是一个 `*types.Var`，可以认为表示一个变量，而`field.Type()`得到的就是这个变量的类型。

有了类型数据，我们就可以有的放矢，决定如何生成 `field` 对应的代码了。

### Method

另一种常见的情况是基于 `interface` 生成实现，比如 `go-kit` 那海量的样板代码。

我们稍微改下上面的代码。

```go
for i := 0; i < tp.NumMethods(); i++ {
    method := tp.Method(i)
    signature := method.Type().(*types.Signature)
    fmt.Printf("func (r Sample) %s(", method.Name())
    for i := 0; i < signature.Params().Len(); i++ {
        param := signature.Params().At(i)
        fmt.Printf("%s %v,", param.Name(), param.Type())
    }
    fmt.Print(")")
    if signature.Results().Len() > 1 {
        fmt.Print(" (")
    }
    for i := 0; i < signature.Results().Len(); i++ {
        result := signature.Results().At(i)
        fmt.Printf("%s %v", result.Name(), result.Type())
        if i+1 < signature.Params().Len() {
            fmt.Print(",")
        }
    }
    if signature.Results().Len() > 1 {
        fmt.Print(" )")
    }
    fmt.Print(" {\n\tpanic(errors.New(\"Not implemented!\"))\n}\n\n")
}
```

并不复杂！

遍历 interface 下的所有方法，然后把 `Params` 和 `Results` 挨个打印出来，函数体里放一个 `panic(errors.New("Not implemented!"))`，就是这样！

最后输出像是这样：

```go
func (r Sample) FirstName() string {
        panic(errors.New("Not implemented!"))
}

func (r Sample) LastName() string {
        panic(errors.New("Not implemented!"))
}
```

值得注意的是，`Method`返回的是 `*types.Func`，但 `Params`和`Results`并不是`types.Func`上的方法，而是 `types.Signature`。官方文档说 `Func`的`Type()`返回的必然是 `*types.Signature`，所以直接断言也是安全的。

## 总结

参考官方的文档 [gotypes](https://github.com/golang/example/tree/master/gotypes)

重点就一个：不要用 `go/types` 下的 `Config` 和 `Checker`，用 `importer.ForCompiler` 从源码获取类型数据。`types`用起来个人感觉比 `go/ast` 方便，缺点是因为引入类型会导致解析源码各方面的消耗增加，算是一个我个人比较偏好的 trade-off 吧。在 codegen 的输入类型比较复杂敏感的时候，拿 `go/types` 替代 `go/ast` 可以省下很多工作量。