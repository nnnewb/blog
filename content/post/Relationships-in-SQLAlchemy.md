---
title: sqlalchemy 各种表关系
date: 2019-03-01 15:52:00
tags: [python, sqlalchemy]
categories:
  - python
---

## 注意事项

### ForeignKey

`db.ForeginKey`的参数是`<表名>.<键名>`，而不是`<类名>.<字段名>`，务必注意这个区别。

### back_populates 和 backref 在多对多关系中使用的区别

`back_populates`是更推荐的写法。

多对多关系中使用`backref`并指定了`secondary`的话，另一张表关联的`relationship`字段会使用相同的`secondary`。

`back_populates`则需要在两张表的`relationship`中都写上相同的`secondary`中间表。

### 可调用的 secondary

`secondary`参数可以是一个可调用对象，做一些 trick 的时候应该有用。姑且记下。

## 一对多关系

```python
class Parent(Base):
    __tablename__ = 'parent'
    id = Column(Integer, primary_key=True)
    child = relationship("Child", back_populates="parent")

class Child(Base):
    __tablename__ = 'child'
    id = Column(Integer, primary_key=True)
    parent_id = Column(Integer, ForeignKey('parent.id'))
    parent = relationship("Parent", back_populates="child")
```

`parent`包含多个`child`的一对多关系。`child`里写`ForeignKey`为`parent`的主键，`child`里写`relationship`，`parent`里同样写`relationship`，`back_populates`填充上，完事。

## 一对一关系

```python
class Parent(Base):
    __tablename__ = 'parent'
    id = Column(Integer, primary_key=True)
    child = relationship("Child", uselist=False, back_populates="parent")

class Child(Base):
    __tablename__ = 'child'
    id = Column(Integer, primary_key=True)
    parent_id = Column(Integer, ForeignKey('parent.id'))
    parent = relationship("Parent", back_populates="child")
```

一对一关系中`parent`需要在`relationship`里加入参数`uselist`，其他相同，完事儿。

## 多对多关系

多对多关系需要一个中间表。

```python
association_table = Table('association', Base.metadata,
    Column('left_id', Integer, ForeignKey('left.id')),
    Column('right_id', Integer, ForeignKey('right.id'))
)

class Parent(Base):
    __tablename__ = 'left'
    id = Column(Integer, primary_key=True)
    children = relationship(
        "Child",
        secondary=association_table,
        back_populates="parents")

class Child(Base):
    __tablename__ = 'right'
    id = Column(Integer, primary_key=True)
    parents = relationship(
        "Parent",
        secondary=association_table,
        back_populates="children")
```

中间表里写上`parent`和`child`的主键作为`foreignkey`，`parent`和`child`里的`relationship`加入参数`secondary`，指定为中间表。
