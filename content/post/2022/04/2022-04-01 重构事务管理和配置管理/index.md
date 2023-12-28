---
title: 记一次重构事务管理和配置管理
slug: refactoring-transaction-and-config-management-note
date: 2022-04-01 12:30:00
categories:
- golang
tags:
- golang
- 重构
---

## 前言

重构发生的背景是这样的。

我手里的项目因为一系列管理上的混乱和不作为导致接手的时候非常糟，总之理解成那种写了一两年代码第一次接触Go没人review代码的半吊子还从单体beego一路跨到非常考验架构能力到编程能力各方面能力的微服务架构结果留下烂摊子跑路了的情况就对啦。

没看懂写的什么鬼？对，我接手项目的时候也是这个感觉。

细看也能读懂，业务逻辑不复杂，但读起来的感觉就像是shit里淘金。

其中有几个特别困扰我的问题：

1. 事务管理凌乱，混用 `xorm` 和`database/sql`，各种拼 sql 和手动管理 `sql.Tx`，分布式事务的问题零关注。
2. 配置极其杂乱，几百条配置项不分用途场景全写成环境变量，结果就是海量的全局变量和极乱的 `func init`。

还有些和主题无关的问题，比如完全没有考虑缓存，现在在屎山上建缓存就非常头疼了；API 设计完全没考虑如何演进，不说 BFF 什么的设计模式，这 API 就完全是毫无设计，到处滥用 protobuf 生成的结构，结果严重耦合，等等种种。这些这里先不提。

对于事务管理和配置管理的问题可以再细细分析。

## 事务管理重构

### 痛点

先看一段重构前的事务代码。

```go
tx, err := DB.Begin()
if err != nil {
    return nil, err
}
rollBack := true
defer func() {
    if rollBack {
        err := tx.Rollback()
        if nil != err {
            log.Error("rollback failed")
        }
    }
}()

// ...

rollBack = false
if err := tx.Commit(); err != nil {
    return nil, err
}
```

还有第二种写法：

```go
var (
    sqlStmts = make([]string, 0, len(req.UserId))
    params   = make([][]interface{}, 0, len(req.UserId))
)

// for ... {
// ...
//     sqlStmts = append(sqlStmts, "update task_answer set is_eva=?,is_excellent=?,eva_text=?,eva_expression=? where task_id=? and user_id=?")
//     params = append(params, []interface{}{constants.True, req.IsExcellent, req.TaskEva.Text, req.TaskEva.Expression, req.TaskId, v})
// }

if err := DB.ExecSqlInTxAndCommit(ctx, sqlStmts, params); err != nil {
    return nil, err
}
```

事务管理上最大的痛点有几个：

- 手工`Commit/Rollback`逻辑较复杂，需要辅助变量或命名返回值，还要处理 `recover`。
- 手工`Commit/Rollback`样板代码多。
- 已有的事务封装效果不佳，拼凑 `sqlStmts []string` 有损可读性，写起来也麻烦。
- 由于上面的原因，很大部分的 CURD 接口都没有事务化处理，存在隐患。
- 显而易见，分布式事务完全没有考虑过。

### 目标

重构的时间成本是很高的，因为重构花的精力不能直接变现成业务价值，对不做编码和架构工作的管理层来说虚无缥缈的“可维护”、“灵活”、“隐患”这样的说辞并不容易被认可。

一般来说，主动提重构要时间（要不到），提方案（大刀阔斧被否），执行（同事觉得你多管闲事），review（长不看），最后背锅（线上crash怎么想都是你的错啦！），这一路闯关下来可不容易。但是...我司管理混乱，我比较闲。

所以能大方地掏出时间搞个没什么业务价值的重构，看看能不能消灭一些隐患，也方便将来我或者下一个接盘侠需要二次开发的时候少吃点苦头。

重构的目标是解决上面的痛点1234，但分布式事务不太好即刻引入。原因也简单，要考虑下用什么框架，`coordinator` 选型，和现有的事务管理体系对接，做线上升级方案，这一系列事情最好等事务管理统一后再做，才可能事半功倍。

### 调研

古人云：

> 它山之石可以攻玉。

所以先看看别的知名框架怎么处理的事务是个好主意。

#### beego

`beego`有两种事务管理方法，第一种是利用闭包：

```go
// Beego will manage the transaction's lifecycle
// if the @param task return error, the transaction will be rollback
// or the transaction will be committed
err := o.DoTx(func(ctx context.Context, txOrm orm.TxOrmer) error {
	// data
	user := new(User)
	user.Name = "test_transaction"

	// insert data
	// Using txOrm to execute SQL
	_, e := txOrm.Insert(user)
	// if e != nil the transaction will be rollback
	// or it will be committed
	return e
})
```

具体实现是很好猜的，`DoTx`里`defer func(){}()`处理下返回值和`recover`，没有错误就提交。这种写法很灵活，也能有效避免忘记`defer`或者`defer`考虑不够全面之类的问题。

`beego`的另一种事务管理方法就是手动`Commit/Rollback`了，和直接用 `sql.Tx` 差别不大，不细说了。

#### gin

`gin`没有官方的事务方案，不过我找到一个社区方案：利用中间件在 `context` 里注入事务对象，业务代码里可以 `GetTransactionFromContext(ctx)` 获取，后续处理没有错误就提交，和 `beego` 的闭包法类似，不过就是把事务从业务代码提到了全局，进一步减少了侵入。

#### django

`django` 是 python 的 web 框架，也有一定参考意义。

`django`的事务主要是靠装饰器实现的：

```python
from django.db import transaction

@transaction.atomic
def viewfunc(request):
    # This code executes inside a transaction.
    do_stuff()
```

也可以用上下文管理器：

```python
from django.db import transaction

def viewfunc(request):
    # This code executes in autocommit mode (Django's default).
    do_stuff()

    with transaction.atomic():
        # This code executes inside a transaction.
        do_more_stuff()
```

关于Python的装饰器和上下文管理器，我简要解释下：

装饰器：高阶函数，接受被装饰函数作为输入，返回新函数。比如

```python
def decorator(f):
    def wrapped(*args,**kwargs):
        return f(*args,**kwargs)
   	return wrapped

@decorator
def fun():
    pass
```

本质上就是

```python
def decorator(f):
    def wrapped(*args,**kwargs):
        return f(*args,**kwargs)
   	return wrapped

def fun():
    pass

fun = decorator(fun)
```

至于上下文管理器，可以简单理解成 `try {} finally {}`。

`django`的思路和`beego`、`gin`是很相似的，因为`python`的装饰器语法存在使得事务管理可以更灵活地在函数级作用域里使用，而不用侵入业务代码。

#### springboot

`springboot`主要利用注解和一系列我也不懂的JVM机制添加事务，具体还是不说了，多说多错。随手搜的一篇参考文章：[Springboot之@Transactional事务注解原理详解](https://juejin.cn/post/7003614270877335560)

```java
public Object invoke(MethodInvocation invocation) throws Throwable {
    Class<?> targetClass = invocation.getThis() != null ? AopUtils.getTargetClass(invocation.getThis()) : null;
    Method var10001 = invocation.getMethod();
    invocation.getClass();
    // 调用事务逻辑
    return this.invokeWithinTransaction(var10001, targetClass, invocation::proceed);
}

@Nullable
protected Object invokeWithinTransaction(Method method, @Nullable Class<?> targetClass, TransactionAspectSupport.InvocationCallback invocation) throws Throwable {
  TransactionAttributeSource tas = this.getTransactionAttributeSource();
  // 获取改方法上的事务配置，包括传播级别、异常信息等配置
  TransactionAttribute txAttr = tas != null ? tas.getTransactionAttribute(method, targetClass) : null;
  // 事务管理器，负责生成事务上下文信息，比如开启事务、获取数据库链接等逻辑
  TransactionManager tm = this.determineTransactionManager(txAttr);
  ...
  PlatformTransactionManager ptm = this.asPlatformTransactionManager(tm);
  String joinpointIdentification = this.methodIdentification(method, targetClass, txAttr);
  // 根据传播级别配置，看是否需要新建事务
  TransactionAspectSupport.TransactionInfo txInfo = this.createTransactionIfNecessary(ptm, txAttr, joinpointIdentification);

  Object retVal;
  // 通过try catch捕获异常来实现回滚逻辑
  try {
  // 调用真正的dao层逻辑
      retVal = invocation.proceedWithInvocation();
  } catch (Throwable var18) {
  // 根据@Transactional配置的异常来决定是否回滚
      this.completeTransactionAfterThrowing(txInfo, var18);
      throw var18;
  } finally {
  // 结束当前的事务，信息是保存在ThreadLocal里
      this.cleanupTransactionInfo(txInfo);
  }

  if (retVal != null && vavrPresent && TransactionAspectSupport.VavrDelegate.isVavrTry(retVal)) {
      TransactionStatus status = txInfo.getTransactionStatus();
      if (status != null && txAttr != null) {
          retVal = TransactionAspectSupport.VavrDelegate.evaluateTryFailure(retVal, txAttr, status);
      }
  }
  // 没有异常时，执行commit操作
  this.commitTransactionAfterReturning(txInfo);
  return retVal;
  ...
  
}
```

可以看到排除 springboot 的机制外，思路依然是清晰易懂的：进入业务逻辑前准备好事务，业务逻辑后没有错误则提交，否则回滚。

上述4种框架的处理方法都是在使用各种语言机制来应用 AOP 思想。

### 方案

考虑到旧代码范围广，闭包模式需要对旧的用法做侵入式修改，工作量大；针对特定业务函数应用装饰器模式在go语言环境下水土不服；唯一可能的选择就是中间件了。

而中间件又有几个选择：

- 针对服务接口封装中间件，优点是可以实现接口级按需注入事务，缺点是写起来啰嗦
- 全局中间件，优点是实现简单，缺点是所有业务接口都会注入事务

更进一步的抽象，比如 `gokit` 架构设计中的对单个业务接口抽出 `Endpoint` ，彻底把业务层和传输层分离，所需的工作量更是离谱。

最终出于review友好也对我的手指友好考虑，还是选择全局中间件，但加改变，同时注入`sql.DB`，并且让事务懒启动，尽量避免多余的`Begin/Commit/Rollback`拖长接口耗时。

这一方案落地为一个`txmanager`包和一个 gRPC Interceptor ，`txmanager` 定义数据库接口、事务接口，以及注册事务等工具函数；Interceptor 在`context`注入数据库和事务，在业务执行完成后，`defer`里 `recover`并检查返回值，决定提交或回滚。

```go
defer func() {
    txSet, ok := ctx.Value(txSetKey).(mapset.Set)
    if !ok {
        return
    }
    defer txSet.Clear()

    if e := recover(); e != nil {
        // 检查 panic
        rollbackTxSet(ctx, txSet)
        panic(e)
    } else if err != nil {
        // 检查 error 返回值
        log.ErrorC(ctx, "rollback due to error", "err", err, "recovered", e)
        rollbackTxSet(ctx, txSet)
    } else if resp != nil && reflect.Indirect(reflect.ValueOf(resp)).FieldByName("Code").Int() != errorcode.RequestSuccess {
        // 检查响应 Code
        log.ErrorC(ctx, "rollback due to response code", "code", reflect.Indirect(reflect.ValueOf(resp)).FieldByName("Code").Int())
        rollbackTxSet(ctx, txSet)
    } else {
        // 没有错误，提交事务
        commitTxSet(ctx, txSet)
        return
    }
}()
```

考虑到旧的代码并不规范，所以一个 `ctx` 是可以可以注入多个数据库和事务的，把事务绑定到上下文的工作只能在微服务代码下再单独写两个工具函数。

```go
func GetBaseDB(ctx context.Context) *sql.DB {
	v := ctx.Value(BaseDBKey)
	if v == nil {
		panic(errors.New("no database found in context"))
	}

	if db, ok := v.(*txmanager.WrappedDB); ok {
		return db.DB
	}
	panic(fmt.Errorf("unexpected database type %T", v))
}

func GetTxForBaseDB(ctx context.Context) *sql.Tx {
	tx, err := txmanager.LazyBeginTx(ctx, BaseDBKey, BaseTxKey)
	if err != nil {
		panic(errors.Wrap(err, "get transaction for base db failed"))
	}
	return tx.(*sql.Tx)
}
```

如此一来，在业务代码里，原本的 `DB.Query`只要改成`GetBaseDB(ctx).Query`即可，影响降至最低。

而原本涉及事务的代码，也可以简单地改写成：

```go
tx := GetTxForBaseDB(ctx)

// ...业务代码
// tx.ExecContext(ctx, query, args...)
```

原本复杂的`defer`就可以直接省略了，`sqlStmts`也可以去除，变成 `tx.ExecContext()` ，读起来更清楚。

### 效果评估

最明显的就是原本考虑不周的 `defer` 里 `Commit/Rollback` 被考虑更全面的中间件替代了，潜在的 `panic`导致错误提交/回滚问题得到修正，相关代码去除后可读性有所改善。

其次是有机会在这个基础上统一封装一个分布式事务，把侵入业务代码的可能降到比较低的水平。

重构完还发现，利用数据库初始化从`init`推迟到`main`的改变，有机会对数据库做mock，可测试性也有改善。

也看了下 jaeger 对请求耗时的分析，重构后的事务管理器增加的耗时不明显，不够成瓶颈，性能上也马马虎虎过得去。压测因为压力直接打到MySQL的原因没法做，QPS瓶颈很明显卡在数据库上，缺少缓存依然是致命短板。

## 配置管理重构

### 痛点

相信很多人写代码的时候习惯把第三方的服务的 key/secret 直接写成常量，然后用一个宏或者标志去控制用哪套配置，比如这样：

```c
#ifdef PRODUCTION
#	define QINIU_AK "***ak***"
#	define QINIU_SK "***SK***"
#elif defined(TESTING)
#	define QINIU_AK "***ak***"
#	define QINIU_SK "***SK***"
#else
#	define QINIU_AK "***ak***"
#	define QINIU_SK "***SK***"
#endif
```

但这项目比较狗，选择用环境变量来配置。用环境变量也就算了，最大的问题是：不管什么东西都往环境变量里塞，所有微服务共用一套环境变量配置，结果环境变量配置足有一百多行，也不管谁在用，怎么用。

这也就罢了...

更离谱的是，连推送文案，居然也写到环境变量里...我寻思这玩意儿不得让运营人员编辑的吗...

在上一份工作里维护的项目就好得多，大部分配置放到了 etcd，比如第三方服务的ak/sk和一些业务配置，也做到了热重载，不需要开发/运维人员介入就能实时调很多东西。而现在的项目，属于是开发的时间不要钱，宁可随时 on call 也不安排写个配置编辑和热重载。

而且还有个比较头疼的问题是，因为配置是环境变量，环境变量又由 kubernetes configmap 管理，kubernetes 配置又和源代码一起被 git 跟踪管理，所以即使是运营人员想改个推送文案，也要走开发的 hotpatch 流程，提交到 git 上，谁都不舒服。

最终列出痛点如下：

- 配置修改不便。
- 不支持按需访问，存在误用滥用。
- 从痛点2延伸出不可控问题，无关配置项配置问题也会导致服务初始化时 crash，倒逼所有服务共用一套环境变量。
- 从痛点1延伸出不灵活问题，即使有修改不便的问题，也不支持更换配置源，存在强耦合。

### 调研

因为配置管理其实是一个和语言关系比较大的领域，配置读写的接口灵不灵活好不好用很大程度看语言有哪些奈斯的语法糖。

比如 python 可以继承 `UserDict` 等结构实现个同时支持`.`语法和下标的配置对象，更高阶的还可以用 `descriptor` 预先定义字段，检查/转换类型等等。

再比如 C++ 就完全可以一套 `template` 打天下，接口完全可以设计成 `get<int>`、`get<std::string>` 这样，也可以利用运算符重载实现 `config["http.port"]` 下标形式的访问，甚至再骚一点，结合一点宏和元编程，`config->http->port` 也行。

对 Go 这样的语言来说事情会更麻烦，一来是静态类型，堵死了一个`Get`覆盖所有情况的路子。除非不介意 `interface{}` 满天飞。二来泛型不成熟，同样堵死了像 C++ 那样一个 `Get[T]` 打天下的路子。

所以调研主要还是考虑有没有现成的轮子，能不能满足需要。

#### viper

*viper* 是一个相当流行的配置管理库，原本是为 *cobra* （一个 cli 库）设计的。

*viper* 支持不少配置源，从配置文件（JSON、TOML、YAML、INI）到环境变量、远程配置（etcd、consul）都能支持，接口设计上也还算舒服（像是`viper.GetString(key)`这样的用法），而且有个比较奈斯的热重载。缺憾是etcd暂时只支持到 v2，而且支持多种配置的方式是嵌入本体，导致 viper 仓库依赖很多。

考虑到 viper 对付目前的需求有点 overkill，而且依赖有点偏多，决定是定义一套读配置接口，先自行实现基于环境变量的配置提供者，若有需要再把读配置接口的实现替换成 viper 。

### 方案

鉴于当前项目中配置项是全局变量+`func init`，替换成配置管理器解决修改不便+热重载的话需要把全局变量换成 `sync.Map` 或者 `GetXxx()` 。考虑到是读多写少的场景，`sync.Map` 有点过，而且把全局变量替换成 `config["Xxx"]` 还会遇到类型问题。

而`GetString`这种形式的接口，又需要把配置名换成字符串，直接用环境变量当 key 的话又会碰到环境变量命名不好、其他配置源命名规则有区别等情况。从使用的角度来说，还是希望尽可能把对业务代码的影响降到最低，因此业务代码里最好还是 `GetQiniuAK() string` 这样的接口最合适，内部实现可以是适配到 `GetString("QINIU_AK")`。

同样有部分痛点无法立即得到解决：

- 误用滥用问题无法完全解决，需要进一步对配置项分析，提取出公共配置和独属于服务的配置。这也会造成新的问题：如何兼顾配置的中心化访问模式（保持`config.GetXxx`这种足够简单清楚的访问方式，不会在业务代码里出现`globalConfig`和`privateConfig`两个配置源）和私有配置防误用滥用？

整体方案如下：

- 原本的全局变量全部改成 `GetXxx() <type>` 形式定义。
- 实现一个`config`包，定义`ConfigReader`接口和初步实现，再给一个全局默认 `ConfigReader` ，方便直接用 `config.GetString(key)` 的形式读配置，降低使用门槛。`ConfigReader`的实现内用一个标准`map`和`sync.RWMutex`管理配置项缓存，降低读操作的成本。

```go
type ConfigReader interface {
	GetString(key string) (string, error)
	GetInt(key string) (int, error)
	GetInt32(key string) (int32, error)
	GetInt64(key string) (int64, error)
	GetUint(key string) (uint, error)
	GetUint32(key string) (uint32, error)
	GetUint64(key string) (uint64, error)
	GetFloat32(key string) (float32, error)
	GetFloat64(key string) (float64, error)
	GetBytes(key string) ([]byte, error)
	GetDuration(key string) (time.Duration, error)
	GetBool(key string) (bool, error)

	MustGetString(key string) string
	MustGetInt(key string) int
	MustGetInt32(key string) int32
	MustGetInt64(key string) int64
	MustGetUint(key string) uint
	MustGetUint32(key string) uint32
	MustGetUint64(key string) uint64
	MustGetFloat32(key string) float32
	MustGetFloat64(key string) float64
	MustGetBytes(key string) []byte
	MustGetDuration(key string) time.Duration
	MustGetBool(key string) bool
}
```

以及配置提供者：

```go
type ConfigProvider interface {
	Lookup(key string) ([]byte, bool)
	Get(key string) ([]byte, error)
	Set(key string, val []byte) error
	Delete(key string) error

	// is config provider support change detection
	CanWatch() bool
	// Optional, implementation may return nil chan
	Watch(ctx context.Context) <-chan Change
}
```

最终指定 Provider 来创建 `ConfigReader` 实例。

这个方案存在一个比较麻烦的问题：原始的全局变量并不都是 `string` 类型，而是夹杂了 `int`、`int64`、`bool`，初始化时有的是用了封装好的 `GetEnv` ，有的使用 `os.Getenv()`、`strconv.Atoi` 等。将原本的全局变量替换成 `GetXxx` 并不是一件简单的事——如果手动来的话。

幸好，Go 提供了 `go/parser`，只需要写大概一两百行代码，处理下 `GenDecl` 和 `AssignStmt`，找出配置项，然后用 `dave/jennifer` 生成对应的 Go 代码即可，最终生成 700多行代码，手工调整下部分结果就算完成了。

至于业务代码中的调用点，可以直接在 vscode 里全局正则表达式搜索 `\benv.(\w+)\b` 替换。

至此，配置管理有了更多的可能。

### 效果评估

- 以较低的成本实现了重构
- 灵活性显著提高，有了迁移配置源到其他存储服务中的可能
- 解决了其他服务的私有配置加载失败也会导致崩溃的问题
- 尚未完全解决配置编辑不便的问题：对于配置迁移到 etcd/consul 等平台，还需要进一步调研选型、决定是改用 viper 还是自行在 etcd/consul driver 上实现一个 provider 。
- 未解决误用滥用问题，仍需考虑如何兼顾中心化访问和私有配置隔离。

## 总结

两项重构的成本均在可控范围内，最终结果只能说勉强，还算是在预期内可接受。距离完全解决痛点仍然有不短的路要走。

真正高价值的重构，比如建立缓存机制，还是需要对相关业务进一步研究理解和思考。