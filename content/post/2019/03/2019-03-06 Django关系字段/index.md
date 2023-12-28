---
title: Django 的各种关系字段详解
author: weak_ptr <weak_ptr@outlook.com>
date: 2019-03-06 21:11:35
tags: ['django', 'python']
categories:
- python
---

> 参考资料如下
>
> - [Django 文档 - Model field reference](https://docs.djangoproject.com/zh-hans/2.1/ref/models/fields/)
> - [SQLAlchemy 中的级联删除](https://graycarl.me/2014/03/24/sqlalchemy-cascade-delete.html)

## 1. ForeignKey

`ForeignKey`用于多对一关系，直接对应到数据库外键的概念。使用`ForeignKey`需要指定引用的目标表，会自动关联到目标表的主键（一般是`id`字段）。

例子如下。

```python
from django.db import models

class Child(models.Model):
    parent = models.ForeignKey('Parent', on_delete=models.CASCADE, )
    # ...

class Parent(models.Model):
    # ...
    pass
```

对比之 sqlalchemy，一行`parent=models.ForeignKey(...)`包含了 sqlalchemy 中的`ForeignKey`和`relationship`两部分内容。

### 1.1 参数：on_delete

`on_delete`意为当`ForeignKey`引用的对象被删除时进行的操作。

有几个可以考虑的选项。

#### 1.1.1 models.CASCADE

`CASCADE`意为级联，`on_delete`设置为`CASCADE`时意为执行级联删除。依据文档，Django 会模仿 SQL 的`ON DELETE CASCADE`，对包含了`ForeignKey`的对象执行删除。

需要注意的是不会调用被级联删除对象上的`model.delete()`，但是会发送[`pre_delete`](https://docs.djangoproject.com/zh-hans/2.1/ref/signals/#django.db.models.signals.pre_delete)和[`post_delete`](https://docs.djangoproject.com/zh-hans/2.1/ref/signals/#django.db.models.signals.post_delete)信号。

#### 1.1.1.2 models.PROTECT

`PROTECT`意为保护，`on_delete`设置为`PROTECT`意味着要阻止删除操作发生。删除关联的对象时，`ForeignKey`的`on_delete`设置为`PROTECT`会触发`ProtectedError`。

#### 1.1.1.3 models.SET_NULL

如其名所述，如果这个`ForeignKey`是 nullable 的，则关联的对象删除时将外键设置为 null。

#### 1.1.1.4 models.SET_DEFAULT

如其名所述，如果这个`ForeignKey`设置了`DEFAULT`，则关联的对象删除时设置这个外键为`DEFAULT`值。

#### 1.1.1.5 models.SET

在关联的对象删除时，设置为一个指定的值。这个参数可以接受一个可以赋值给这个 ForeignKey 的对象或者一个可调用对象。

官方例子如下。

```python
from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import models

def get_sentinel_user():
    return get_user_model().objects.get_or_create(username='deleted')[0]

class MyModel(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET(get_sentinel_user),
    )
```

#### 1.1.1.6 models.DO_NOTHING

应该不用多说了吧。Django 不会做多余的事情，但是如果后端的数据库服务有强制完整性约束，除非你在数据库一端自己定义了`ON DELETE`，否则会触发`IntegrityError`。

### 1.2 参数：limited_choice_to

强制约束为 django.admin 或者 ModelForm 渲染时提供有限的可选项。

接受参数为`dict`或者`Q`对象、返回`Q`对象的可调用对象。

官方例子。

```python
staff_member = models.ForeignKey(
    User,
    on_delete=models.CASCADE,
    limit_choices_to={'is_staff': True},
)
```

Q 对象是什么玩意儿这个我搞明白了再说...

### 1.3 参数：related_name

设置反向关联的字段名，和`sqlalchemy`的`backref`类似。

举例来说。

```python
class Child(models.Model):
    parent = models.ForeignKey('Parent')

class Parent(models.Model):
    pass

Parent.child_set.all() # 未设置 related_name
Parent.children.all() # 设置 related_name=children
```

### 1.4 参数：related_query_name

related_query_name 和 related_name 类似，设置反向引用查询时条件的前缀名。举例来说。

```python
class Child(models.Model):
    parent = models.ForeignKey('Parent')
    name = models.CharField(max_length=4)

class Parent(models.Model):
    pass

Parent.objects.filter(Child__name='沙雕网友') # 未设置 related_query_name
Parent.objects.filter(myboy__name='沙雕网友') # 设置 related_query_name=myboy
```

### 1.5 参数：to_field

得到`ForeignKey`关联的模型的字段，默认是主键，如果指定的不是主键那么必须有`unique`约束才行。

### 1.6 参数：db_constraint

要不要创建数据库层级的约束，也就是通过后端数据库服务确保数据完整性不受破坏。如果设置为 False 那么访问不存在的对象时会触发 DoesNotExists 异常。

### 1.7 参数：swappable

用于处理“我有一个抽象类模型但是这个模型有一个外键”的情况，典型就是`AUTH_USER_MODEL`。

一般不用改到，这个属性控制了数据库迁移时如何处理这个外键关联的表，总之保持默认值就行了。

这个功能支持了使用自定义的用户模型替代 `django.auth.models.User` 之类的玩意儿。

## 2. OneToOneField

`OneToOneField` 基本就是一个加了`unique`约束的`ForeignKey`。使用上与 ForeignKey 略有不同。

首先是访问 `OneToOneField` 时，得到的不是 `QuerySet` 而是一个对象实例。

```python
# 优生优育政策（
class Parent(models.Model):
    child = OneToOneField('Child')

class Child(models.Model):
    pass

parent.child # => 得到一个 Child 实例
```

其次是反向引用的名字是模型名字小写。

```python
child.parent # => 得到一个 Parent 实例
```

如果指定 `related_name` 那就和 `ForeignKey` 一个表现。

## 3. ManyToManyField

基本和`ForeignKey`相同。

### 3.1 和 `ForeignKey` 相同的参数

- related_name
- related_query_name
- limited_choices_to
- db_constraint
- swappable

limited_choices_to 在指定自定义中间表的情况下无效。

### 3.2 参数：symmetrical

用于处理一个表自己对自己的多对多引用对称性。

Django 的默认行为是，我是你的朋友，那么你就是我的朋友。

设置了这个参数则强迫 Django 改变这个行为，允许“被朋友”。

### 3.3 参数：through

默认情况下，Django 会自行创建中间表，这个参数强制指定中间表。

默认中间表模型里包含三个字段。

- id
- &lt;containing_model&gt;\_id
- &lt;other_model&gt;\_id

如果是自己和自己的多对多关系，则

- id
- from\_&lt;model&gt;\_id
- to\_&lt;model&gt;\_id

### 3.4 参数：through_fields

当自行指定中间表，中间表又包含了多个外键时，指定关联的外键用。

举例。

```python
class ModelA(models.Model):
    b = models.ManyToManyField(ModelB, through='ModelC')

class ModelB(models.Model):
    pass

class ModelC(models.Model):
    a=models.ForeignKey('ModelA')
    b=models.ForeignKey('ModelB')
    c=models.ForeignKey('ModelA')
```

此时在中间表中`a`和`c`都是对`ModelA`的外键，产生了歧义，Django 无法自行决定用哪个外键来关联 AB 两个表。

这时提供参数。

```python
b = models.ManyToManyField('ModelB', through='ModelC', through_fields=(a, b))
```

`ManyToManyField` 关联两个表总是不对称的关系（指我把你当兄弟，你却想当我爸爸这样的关系。此时“我”对“你”的“兄弟”关系就是单向的。），这就形成了**来源**和**目标**的概念。

`through_fields` 的第一个元素总被认为是**来源**字段，第二个元素是**目标**字段。

### 3.5 参数：db_table

指定 Django 创建的中间表的名字，默认根据两个表表名和 `ManyToManyField` 的名字决定。
