---
date: 2019-02-21 17:53:00
title: 利用 descriptor 实现自己的 property
tags:
  - python
categories:
  - python
---

## 1.概念简介

### 1.1 property

在 python 代码中，property 是非常常见的一个内置函数。property 可以为一个 python 类的 attribute 设置 getter/setter，可以类比之 C# 的 [properties](https://docs.microsoft.com/zh-cn/dotnet/csharp/language-reference/language-specification/classes#properties)。

见下面的例子。

```python
class A:
    def __init__(self):
        self.a = 1

    @property()
    def hello(self):
        return self.a

    @hello.setter()
    def hell(self, value):
        self.a = value

print(A().hello)
# output:
# 1
obj = A()
obj.hello = "hello world"
print(obj.hello)
# output:
# hello world
```

### 1.2 descriptor

python 中的 descriptor 指的是实现了`__get__`、`__set__`、`__delete__`三个方法之一的类。

当一个 descriptor 类的实例作为其他类的成员时，通过`obj.attr`语法访问该实例将会调用 descriptor 实例的`__get__`方法。同理，`__set__`和`__delete__`也是相似的逻辑。

先看个例子。

```python
class DescriptorClass:
    def __get__(self, instance, owner):
        print(self)
        print(instance)
        print(owner)
        return 'some value'

class SomeClass:
    some_attr = DescriptorClass()

print(SomeClass().some_attr)

# output:
# <__main__.DescriptorClass object at 0x0000027AAE777160>
# <__main__.SomeClass object at 0x0000027AAE777198>
# <class '__main__.SomeClass'>
# some value
```

## 2. 实现

property 的逻辑在于，**当实例访问这个属性时，调用方法**。descriptor 刚好处在那个正确的位置上。

看代码。

```python
class PropertyDescriptor:
    def __init__(self, fn):
        self.getter = fn

    def __get__(self, instance, owner):
        return self.getter(instance)

    def __set__(self, instance, value):
        return self.setter(instance, value)

    def setter(self, func):
        self.setter = func
        return self

def my_property(func):
    return PropertyDescriptor(func)

class SimpleClass:
    @my_property
    def simple_attr(self):
        return 'a simple property'

    @simple_attr.setter
    def simple_attr(self, value):
        print('simple attr setter')

print(SimpleClass().simple_attr)
SimpleClass().simple_attr = 'something'

# output:
# a simple property
# simple attr setter
```

## 3. 总结

> 个人看法，谨慎参考

descriptor 避免了重复编写`getter`和`setter`方法，非常直觉的一种用途就是类似于`SQLAlchemy`这样的 ORM 框架的的字段映射。不需要为每一个特定类型的字段在基类或元类里编写大量样板代码。

但这种设计是侵入式的（需要修改目标类的代码），而且非常不直观。在合适的地方使用相信可以有其发光发热的空间。

对可读性来讲，结合元类，这俩被一起滥用的话对维护者而言完全是地狱吧...
