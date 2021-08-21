---
title: 面试题之 goroutine 运行顺序
date: 2021-08-04 10:37:24
categories:
  - golang
tags:
  - golang
---

不是我做的沙雕面试题，在 segmentfault 上看到的。

<!-- more -->

## 原题

```go
package main

import (
    "fmt"
    "runtime"
    "sync"
)

func main() {
    runtime.GOMAXPROCS(1)
    wg := sync.WaitGroup{}
    wg.Add(10)
    for i := 0; i < 5; i++ {
        go func() {
            fmt.Println("A:", i)
            wg.Done()
        }()
    }
    for i := 0; i < 5; i++ {
        go func(num int) {
            fmt.Println("B:", num)
            wg.Done()
        }(i)
    }
    wg.Wait()
}
```

问：代码输出结果是什么？

## 胡乱分析

第一眼进去看到 `runtime.GOMAXPROCS(1)` ，初步怀疑是又在考什么 GMP 面试题了。

但凡说到 Go 面试好像就一定要考一下 goroutine 调度和 GMP 模型，招进来又只让你写 curd 。搞得面试跟考试背书一样。

先不吐槽，继续看。跳过两行 `sync.WaitGroup` 之后就是一个经典 for 循环陷阱。

```go
for i := 0; i < 5; i++ {
    go func() {
        fmt.Println("A:", i)
        wg.Done()
    }()
}
```

就是个典型的闭包捕获问题，`i` 被以引用形式捕获进匿名函数，循环中的 `i++` 会导致所有匿名函数捕获的 `i` 的值都跟着变。

但有所区别的是，这个匿名函数被当 goroutine 执行了。之后再细说。

```go
for i := 0; i < 5; i++ {
    go func(num int) {
        fmt.Println("B:", num)
        wg.Done()
    }(i)
}
```

这就是上面错误例子的正确写法，把闭包捕获变成了参数传递，将 `i` 复制了一份进匿名函数。

好了，那么根据上面的分析，最终结果是...？

```text
A: 5
A: 5
A: 5
A: 5
A: 5
B: 0
B: 1
B: 2
B: 3
B: 4
```

是这样吗？

## 再次胡乱分析

遗憾的是实际跑起来结果是

```text
B: 4
A: 5
A: 5
A: 5
A: 5
A: 5
B: 0
B: 1
B: 2
B: 3
```

可以看到最后一个启动的 goroutine 的输出跑到了最开头。其他顺序倒是没啥变化。为啥呢？

先看 `runtime.GOMAXPROCS(1)` 。

{% asset_img G-M-P.png %}

从 GMP 模型可以得知这一句代码实际限制了所有 goroutine 只能被顺序串行执行（所有 g 都只能在这唯一一个 p 的本地队列里等待 m）。

而 `main()` 函数里创建 goroutine 的顺序是明确的，5 个 A，5 个 B。

按照一般理解的话，队列是先进先出 FIFO 的结构，一个 p 又限制了其他 m 即使唤醒了，抢占了 p，也不能做 work stealing（也用不着做），那么 goroutine 的执行顺序自然只能是先进先出了。

那么这个程序的行为就很奇怪了，先创建的 goroutine 先执行的话，那么输出顺序应该和我们预料的一样。实际运行结果为什么会变成这样呢？

## 不卖关子了

直接说结论嗷。

**不知道。**

别笑，真的不知道。特地上[爆栈搜了下](https://stackoverflow.com/questions/35153010/goroutines-always-execute-last-in-first-out)，得到的结论就是，不知道。

> In Go 1.5, the order in which goroutines are scheduled has been changed. **The properties of the scheduler were never defined by the language**, but programs that depend on the scheduling order may be broken by this change. We have seen a few (erroneous) programs affected by this change. If you have programs that implicitly depend on the scheduling order, you will need to update them.

从一个 Go 语言使用者的角度来说，goroutine 调度器的实现细节（像是多个 goroutine 之间的运行顺序）并不是能依赖的东西。

如果写过一段时间的 C/C++ ，那么面试官应该很清楚，C/C++ 有几样臭名昭著的东西： _Undefined Behavior_, _Unspecified Behavior_。而 goroutine 执行顺序就是一个 Go 中的 _Undefined Behavior_。

## 结论

我理解中的拿来主义，既不能被动地等待，也不能不加分辨地拿来，而既然加以分辨了，自然更不应该将拿来的事物当成解决一切问题的万能药。

Go 虽然是一门不错的语言，试图将语言细节尽可能明确定义来避免再次陷入 C/C++的陷阱，但显然 Go 用户不这么想。至少，有部分 Go 用户不这么想，他们想搞清楚 Go 的一切，然后把这一切都当作至高无上的准则，来鞭挞其余人。

目前为止，GMP 很好，作为面试题也说得过去。

到底我只是厌恶这世上的一部分人罢了。
