---
title: pattern-match-in-python310
date: 2021-03-19 10:19:06
tags:
- python
categories:
- python
---

## 说明

简单机翻润色一下 PEP-636

## 概要

这个PEP是PEP 634引入的模式匹配教程。

PEP 622提出了模式匹配的语法，社区和指导委员会对此进行了详细讨论。一个常见的问题是解释(和学习)这个特性是否容易。这个PEP关注的是提供开发人员可以用来学习Python中的模式匹配的文档类型。

PEP 636 被认为是PEP 634(模式匹配的技术规范)和PEP 635(模式匹配的添加动机和理由与设计考虑)的支持材料。

对于想要快速回顾而不是教程的读者，请参阅附录a。

## 教程

作为本教程的一个例子，你将编写一个文本冒险游戏。这是一种互动小说形式，用户输入文本命令与虚构世界进行互动，并接收关于所发生事情的文本描述。命令将是简化形式的自然语言，如`get sword`，`attack dragon`，`go north`，`enter shop`或`but cheese`。

### 匹配序列

你的主循环将需要从用户那里获取输入，并将它分割成单词，例如一个像这样的字符串列表:

```python
command = input("What are you doing next? ")
# analyze the result of command.split()
```

下一步是解读这些单词。我们的大多数命令都有两个词:一个动作和一个对象。所以你可能会忍不住这样做:

```python
[action, obj] = command.split()
... # interpret action, obj
```

这行代码的问题在于它遗漏了一些东西：如果用户输入的单词多于或少于2个单词怎么办?为了防止这个问题，您可以检查单词列表的长度，或者捕获上面的语句将引发的`ValueError`。

或者，你可以使用`match`语句来代替:

```python
match command.split():
    case [action, obj]:
        ... # interpret action, obj
```

`match`语句计算**“subject”**(`match`关键字后面的值)，并根据模式(`case`旁边的代码)检查它。一个模式可以做两件不同的事情:

- 验证 subject 具有一定的结构。在您的示例中，`[action, obj]`模式匹配任何恰好包含两个元素的序列。这叫做 **maching**。
- 它将模式中的一些名称绑定到 subject 的组件元素。在本例中，如果列表有两个元素，它将绑定`action = subject[0]`和`obj = subject[1]`。

如果匹配，则`case`块内的语句将与绑定的变量一起执行。如果没有匹配，则什么也不发生，然后执行`match`之后的语句。

注意，与解包赋值(unpacking assignments)的方式类似，您可以使用圆括号、方括号或逗号分隔，它们含义相同。所以你可以写`case action, obj`或者`case (action, obj)`。上述任意形式都将匹配序列类型(例如`list`或`tuple`)。

```python
# 译者补充，下述case等效
match [1,2,3]: # match (1,2,3) 也一样
    case a,b,c:
        ...
    case (a,b,c):
        ...
    case [a,b,c]:
        ...
```

### 匹配多个模式

即使大多数命令都是动作/对象形式，你也可能想要不同长度的用户命令。例如，你可能希望添加没有对象(如`look`或`quit`)的单个动词。一个`match`语句可以(而且很可能)有不止一种情况:

```python
match command.split():
    case [action]:
        ... # interpret single-verb action
    case [action, obj]:
        ... # interpret action, obj
```

`match`语句将从上到下检查模式。如果模式与 subject 不匹配，将尝试下一个模式。但是，一旦找到第一个匹配的模式，就会执行该`case`的主体，并忽略所有后续的`case`。这类似于`if`/`elif`/`elif`/…语句的工作方式。

### 匹配特定值

你的代码仍然需要查看特定的操作，并根据特定的操作有条件地执行不同的逻辑(例如，`quit`、`attack`或`buy`)。你可以使用`if`/`elif`/`elif`/…，或者使用函数字典，但是这里我们将利用模式匹配来解决这个任务。除了变量，你可以在模式中使用字面值(如`"quit"`、`42`或`None`)。这允许你这样写:

```python
match command.split():
    case ["quit"]:
        print("Goodbye!")
        quit_game()
    case ["look"]:
        current_room.describe()
    case ["get", obj]:
        character.get(obj, current_room)
    case ["go", direction]:
        current_room = current_room.neighbor(direction)
    # The rest of your commands go here
```

像`["get"， obj]`这样的模式将只匹配第一个元素等于`"get"`的2个元素的序列。它还将绑定`obj = subject[1]`。

正如您在上述代码的`go`模式中看到的，我们还可以在不同的模式中使用不同的变量名。

除了与`is`操作符比较的常量`True`、`False`和`None`之外，其他字面值是用`==`操作符比较的。

### 匹配多个值

玩家可以通过使用一系列的命令来投掷多个物品，如:`drop key`, `drop sword`, `drop cheese`。这个接口可能很麻烦，您可能希望允许在一个命令中添加多个项，比如`drop key sword cheese`。在这种情况下，你事先不知道命令中有多少个单词，但是你可以在模式中使用扩展解包(extended unpacking)，就像它们在解包赋值里的写法:

```python
match command.split():
    case ["drop", *objects]:
        for obj in objects:
            character.drop(obj, current_room)
    # The rest of your commands go here
```

这将匹配任何以`“drop”`作为第一个元素的序列。所有剩余的元素都将在一个列表对象中被捕获，该列表对象将绑定到`objects`变量。

这种语法与序列解包有类似的限制:在一个模式中不能有多个带星号的名称。

### 添加通配符

您可能希望打印一条错误消息，说明当所有模式都失败时，无法识别该命令。您可以使用我们刚刚学习的特性，并将`case [*ignored_words]`作为您的最后一个模式。然而，有一个更简单的方法:

```python
match command.split():
    case ["quit"]: ... # Code omitted for brevity
    case ["go", direction]: ...
    case ["drop", *objects]: ...
    ... # Other cases
    case _:
        print(f"Sorry, I couldn't understand {command!r}")
```

这个特殊的模式被写成`_`(称为通配符)。不管 subject 是什么它总是能匹配到，但它不绑定任何变量。

注意，这将匹配任何对象，而不仅仅是序列。因此，只有将它单独作为最后一个模式才有意义(为了防止错误，Python会阻止您在其他`case`之前使用它)。

### 模式组合

这是一个很好的时机，可以从示例中退后一步，了解您一直在使用的模式是如何构建的。模式可以相互嵌套，我们已经在上面的例子中隐式地这样做了。

我们已经看到了一些“简单”模式(这里的“简单”意味着它们不包含其他模式):

- 捕获模式 Capture patterns (独立名称，如方向、动作、对象)。我们从未单独讨论过这些，而是将它们作为其他模式的一部分使用。
- 字面值模式 Literal patterns (字符串字面值、数字字面值、`True`、`False`和`None`)
- 通配符模式 Wildcard pattern `_`

到目前为止，我们实验过的唯一一个非简单模式是序列模式。序列模式中的每个元素实际上都可以是任何其他模式。这意味着您可以编写像`["first"， (left, right)， _， *rest]`这样的模式。匹配的 subject 是一个至少包含三个元素的序列，其中第一个元素等于`"first"`，第二个元素依次是两个元素的序列。它也会绑定`left=subject[1][0]`， `right=subject[1][1]`，`rest =subject[3:]`

### or 模式

回到冒险游戏的例子中，你可能会发现你想要一些导致相同结果的模式。例如，您可能希望命令`north`和`go north`相等。您可能还希望为`get X`可以有一些别名如`pick x up`和`pick up x`。

模式中的|符号将它们组合为可选项。你可以这样写:

```python
match command.split():
    ... # Other cases
    case ["north"] | ["go", "north"]:
        current_room = current_room.neighbor("north")
    case ["get", obj] | ["pick", "up", obj] | ["pick", obj, "up"]:
        ... # Code for picking up the given object
```

这被称为**or模式**，并将产生预期的结果。模式从左到右尝试；如果有多个可选匹配，通过从左至右这一规则可以知道是匹配到了哪个模式。在编写or模式时，一个重要的限制是所有备选项都应该绑定相同的变量。所以模式`[1,x] | [2, y]`是不允许的，因为它会使匹配成功后绑定哪个变量变得不清楚。`[1, x] | [2, x]`非常好，如果成功，将始终绑定`x`。

### 捕获匹配的子模式

我们的`“go”`命令的第一个版本是用`[“go”，direction]`模式编写的。我们在上一个版本中使用模式`["north"] | ["go"， "north"]`所做的改变有一些好处，但也有一些缺点:最新版本允许别名，但也有硬编码的方向别名`"north"`，这将迫使我们实际上有独立的模式，`north`/`south`/`east`/`west`。这将导致一些代码重复，但同时我们得到了更好的输入验证，并且如果用户输入的命令是`“go figure!”`而不是方向，我们将不会进入那个分支。

我们可以试着在两个方面都做到最好(为了简洁，我省略了不使用`“go”`的别名版本):

```python
match command.split():
    case ["go", ("north" | "south" | "east" | "west")]:
        current_room = current_room.neighbor(...)
        # how do I know which direction to go?
```

这段代码是一个单独的分支，它验证`“go”`之后的单词是否确实是一个方向。但移动玩家的代码需要知道选择了哪一个，但却无法做到这一点。我们需要的是一个行为类似于or模式但同时进行捕获的模式。我们可以使用**as模式**:

```python
match command.split():
    case ["go", ("north" | "south" | "east" | "west") as direction]:
        current_room = current_room.neighbor(direction)
```

as模式匹配左边的任何模式，同时也将值绑定到名称。

### 添加条件到模式

我们上面探讨的模式可以做一些强大的数据过滤，但有时您可能希望得到布尔表达式的全部功能。假设您实际上希望只允许`“go”`命令出现在基于从`current_room`的可能出口的受限方向集合中。我们可以通过在我们的案例中增加一个 **guard** 来实现这一点。guard 由 if 关键字后跟任意表达式组成:

```python
match command.split():
    case ["go", direction] if direction in current_room.exits:
        current_room = current_room.neighbor(direction)
    case ["go", _]:
        print("Sorry, you can't go that way")
```

guard 不是模式的一部分，而是 case 的一部分。它只在模式匹配，并且所有模式变量都被绑定之后检查(这就是为什么条件可以在上面的例子中使用`direction`变量)。如果模式匹配且条件为真，则 case body 正常执行。如果模式匹配，但条件为假，`match`语句继续检查下一个条件，就好像模式没有匹配一样(可能的副作用是已经绑定了一些变量)。

### 添加UI: 匹配对象

你的冒险游戏正走向成功，你被请求为游戏实现一个图形界面。您所选择的UI工具包允许您编写一个事件循环，您可以通过调用`event.get()`来获取一个新的事件对象。根据用户的动作，结果对象可以有不同的类型和属性，例如:

- 当用户按下某个键时，将生成`KeyPress`对象。它有一个`key_name`属性，其中包含所按键的名称，以及一些有关修饰符的其他属性。
- 当用户单击鼠标时，将生成一个`Click`对象。它有一个指针坐标的属性`position`。
- 当用户点击游戏窗口的关闭按钮时，会生成一个`Quit`对象。

与其编写多个`isinstance()`检查，你可以使用模式来识别不同类型的对象，也可以将模式应用到其属性上:

```python
match event.get():
    case Click(position=(x, y)):
        handle_click_at(x, y)
    case KeyPress(key_name="Q") | Quit():
        game.quit()
    case KeyPress(key_name="up arrow"):
        game.go_north()
    ...
    case KeyPress():
        pass # Ignore other keystrokes
    case other_event:
        raise ValueError(f"Unrecognized event: {other_event}")
```

像`Click(position=(x, y))`这样的模式仅在事件类型是`Click`类的子类时才匹配。它还要求事件具有一个与`(x, y)`模式匹配的位置属性。如果匹配，则局部变量`x`和`y`将得到期望的值。

像`KeyPress()`这样不带参数的模式将匹配任何`KeyPress`类实例的对象。只有在模式中指定的属性才会匹配，其他任何属性都将被忽略。

### 匹配位置属性

前一节描述了在进行对象匹配时如何匹配命名属性。对于某些对象，可以方便地根据位置描述匹配的参数(特别是当只有几个属性并且它们有“标准”排序时)。如果您正在使用的类是命名元组 `namedtuple` 或数据类 `dataclass`，那么您可以按照构造对象时使用的相同顺序来实现这一点。例如，如果上面的UI框架像这样定义它们的类:

```python
from dataclasses import dataclass

@dataclass
class Click:
    position: tuple
    button: Button
```

然后你可以重写你的匹配语句来匹配上面的 subject:

```python
match event.get():
    case Click((x, y)):
        handle_click_at(x, y)
```

`(x, y)`模式将自动匹配`position`属性，因为模式中的第一个参数对应于数据类定义中的第一个属性。

其他类的属性没有自然的顺序，因此需要在模式中使用显式名称来匹配它们的属性。但是，也可以手动指定属性的顺序，允许位置匹配，就像下面这个替代定义:

```python
class Click:
    __match_args__ = ["position", "button"]
    def __init__(self, position, button):
        ...
```

`__match_args__`特殊属性定义了可以在`case Click((x,y))`等模式中使用的属性的显式顺序。

### 匹配常量和枚举

上面的模式对所有鼠标按钮都一视同仁，但您已经决定只接受鼠标左键单击事件，而忽略其他鼠标按键。在做这一修改时，您注意到`button`属性被定义为一个`Button`，这是一个用`enum.Enum`构建的枚举。实际上，你可以像这样匹配枚举值:

```python
match event.get():
    case Click((x, y), button=Button.LEFT):  # This is a left click
        handle_click_at(x, y)
    case Click():
        pass  # ignore other clicks
```

这将适用于任何带点的名称(如`math.pi`)。然而，非限定名称(即没有点的裸名称)将总是被解释为捕获模式，因此在模式中始终使用限定常量可以避免这种歧义。

### 走进云服务：匹配字典

你决定制作游戏的在线版本。您的所有逻辑都将在服务器中，而客户端中的UI将使用JSON消息进行通信。通过json模块，这些将被映射到Python字典、列表和其他内置对象。

我们的客户端将收到一个字典列表(从JSON解析)，包含了要采取的动作，每个元素的查找示例如下:

- `{"text": "The shop keeper says 'Ah! We have Camembert, yes sir'", "color": "blue"}`
- 如果客户端应该暂停`{"sleep": 3}`
- 播放声音 `{"sound": "filename.ogg", "format": "ogg"}`

到目前为止，我们的模式已经处理了序列，但是也有一些模式可以根据它们当前的键匹配映射。在这种情况下，你可以使用:

```python
for action in actions:
    match action:
        case {"text": message, "color": c}:
            ui.set_text_color(c)
            ui.display(message)
        case {"sleep": duration}:
            ui.wait(duration)
        case {"sound": url, "format": "ogg"}:
            ui.play(url)
        case {"sound": _, "format": _}:
            warning("Unsupported audio format")
```

映射模式中的键需要是字面值，但是值可以是任何模式。与序列模式一样，所有子模式都必须匹配通用模式才能匹配。

您可以在映射模式中使用`**rest`来捕获 subject 中的附加键。请注意，如果你忽略了这一点，在匹配时，主题中的额外键将被忽略，例如，消息`{"text": "foo"， "color": "red"， "style": "bold"}`将匹配上面例子中的第一个模式。

### 匹配内建类 builtin classes

上面的代码可以需要一些验证。如果消息来自外部源，则字段的类型可能是错误的，从而导致错误或安全问题。

任何类都是有效的匹配目标，其中包括`bool`、`str`或`int`等内置类，这允许我们将上面的代码与类模式结合起来。因此，我们可以使用 `{"text": str() as message, "color": str() as c}`来代替`{"text": message, "color": c}`来确保`message`和`c`都是字符串。对于许多内置类(参见PEP-634了解整个列表)，可以使用位置参数作为简写，写成`str(c)`而不是`str() as c`。完全重写的版本如下所示:

```python
for action in actions:
    match action:
        case {"text": str(message), "color": str(c)}:
            ui.set_text_color(c)
            ui.display(message)
        case {"sleep": float(duration)}:
            ui.wait(duration)
        case {"sound": str(url), "format": "ogg"}:
            ui.play(url)
        case {"sound": _, "format": _}:
            warning("Unsupported audio format")
```

## 附录A -- 快速入门

`match`语句接受一个表达式，并将其值与作为一个或多个`case`块给出的模式进行比较。这看起来类似于C、Java或JavaScript(以及许多其他语言)中的`switch`语句，但功能要强大得多。

最简单的形式是将一个 subject 值与一个或多个字面值进行比较:

```python
def http_error(status):
    match status:
        case 400:
            return "Bad request"
        case 404:
            return "Not found"
        case 418:
            return "I'm a teapot"
        case _:
            return "Something's wrong with the Internet"
```

注意最后一块:“变量名”`_`充当通配符，永远不会失败。

你可以使用`|` ("or")将几个字面值组合在一个模式中:

```python
case 401 | 403 | 404:
    return "Not allowed"
```

模式看起来就像解包赋值，可以用来绑定变量:

```python
# point is an (x, y) tuple
match point:
    case (0, 0):
        print("Origin")
    case (0, y):
        print(f"Y={y}")
    case (x, 0):
        print(f"X={x}")
    case (x, y):
        print(f"X={x}, Y={y}")
    case _:
        raise ValueError("Not a point")
```

仔细研究一下那个!第一个模式有两个字面量，可以认为是上面所示字面量模式的扩展。但是接下来的两个模式组合了一个字面量和一个变量，变量绑定来自 subject (`point`)的值。第四个模式捕获两个值，这使得它在概念上类似于解包赋值`(x, y) = point`。

如果你使用类来构造数据，你可以使用类名后跟一个类似构造函数的参数列表，但是可以将属性捕获到变量中:

```python
class Point:
    x: int
    y: int

def where_is(point):
    match point:
        case Point(x=0, y=0):
            print("Origin")
        case Point(x=0, y=y):
            print(f"Y={y}")
        case Point(x=x, y=0):
            print(f"X={x}")
        case Point():
            print("Somewhere else")
        case _:
            print("Not a point")
```

你可以在一些内置类中使用位置参数，这些类为它们的属性(例如数据类)提供排序。你也可以通过在你的类中设置`__match_args__`特殊属性来定义模式中属性的特定位置。如果它被设置为`("x"， "y")`，以下模式都是等价的(并且都将`y`属性绑定到`var`变量):

```python
Point(1, var)
Point(1, y=var)
Point(x=1, y=var)
Point(y=var, x=1)
```

模式可以任意嵌套。例如，如果我们有一个简短的点列表，我们可以这样匹配:

```python
match points:
    case []:
        print("No points")
    case [Point(0, 0)]:
        print("The origin")
    case [Point(x, y)]:
        print(f"Single point {x}, {y}")
    case [Point(0, y1), Point(0, y2)]:
        print(f"Two on the Y axis at {y1}, {y2}")
    case _:
        print("Something else")
```

我们可以向模式添加一个`if`子句，称为“guard”。如果 guard 为假，`match` 继续尝试下一个`case`块。注意，值捕获发生在guard求值之前:

```python
match point:
    case Point(x, y) if x == y:
        print(f"Y=X at {x}")
    case Point(x, y):
        print(f"Not on the diagonal")
```

其他几个关键功能:

- 与解包赋值一样，元组和列表模式具有完全相同的含义，并且实际上匹配任意序列。一个重要的异常是它们**不匹配**迭代器或字符串。(技术上讲，subject 必须是`collections.abc.Sequence`的一个实例。)

- 序列模式支持通配符:`[x, y， *rest]`和`(x, y， *rest)`在解包赋值时的工作类似于通配符。*后面的名称也可以是`_`，所以`(x, y， *_)`匹配至少有两个项的序列，而不绑定其余的项。

- 映射模式:`{"bandwidth": b， "latency": l}`从字典中捕获`"bandwidth"`和`"latency"`值。与序列模式不同，额外的键被忽略。还支持通配符`**rest`。(但是`**_`是多余的，所以不允许。)

- 可以使用as关键字捕获子模式:

  ```python
  case (Point(x1, y1), Point(x2, y2) as p2): ...
  ```

- 大多数字面值的比较是`==`的，但是单例的`True`、`False`和`None`是通过`id`进行比较的。

- 模式可以使用命名的常量。这些必须用点命名，以防止它们被解释为捕获变量:

  ```python
  from enum import Enum
  class Color(Enum):
      RED = 0
      GREEN = 1
      BLUE = 2
  
  match color:
      case Color.RED:
          print("I see red!")
      case Color.GREEN:
          print("Grass is green")
      case Color.BLUE:
          print("I'm feeling the blues :(")
  ```

## 原文档版权声明

This document is placed in the public domain or under the CC0-1.0-Universal license, whichever is more permissive.

Source: https://github.com/python/peps/blob/master/pep-0636.rst