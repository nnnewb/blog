---
title: 一个s表达式求值器
slug: a-s-exp-evaluator
date: 2021-12-09 17:11:00
categories:
- golang
tags:
- golang
- gocc
- 编译技术
- scheme
---

## 前言

翻没看过的藏书的时候找出一本《SICP》的 PDF（PS：已经买了正版书），想起曾经拿 Rust 写玩具解释器，结果现在连 Rust 本身都已经快忘光了。

所以就当怀旧，写个很简单的玩具，s表达式求值器。

## 技术栈

语言选择了 Go，用 gocc 生成 Parser/Lexer 。虽然说手写+调试 Lexer/Parser 也是挺快乐的，但毕竟只是怀旧重温下当年愣头青的自己，不想花太多时间。

## 词法定义

简单解释下 gocc 定义词法元素的 DSL 是怎么回事。gocc 的这个 DSL 是类似于 EBNF 的语法（自称）， `_letter: 'a'-'z'` 就是一条产生式，`:`前面是产生式的名称，后面是模式。

产生式名称也有特殊含义。

- `!` 开头的产生式会被 Lexer 忽略。
- `_` 开头的产生式叫做 `regDefId`，可以理解成给后面的模式定义的别名。
- `a-z`小写字母开头的是 `token`，也就是一般说的词法元素定义了。

值得注意的是 `token` 不能被用作其他词法元素产生式的模式部分，但 `regDefId` 可以，所以要注意要复用的规则应该定义成下划线开头。

比如说下面的例子。

```plaintext
// example 1
letter: 'a'-'z';
identifier: letter; // Error!

// example 2
_letter: 'a'-'z';
identifier: _letter; // OK
```

下面是求值器的词法元素定义。

```plaintext
!whitespace: ' ' | '\t' | '\r' | '\n';
!comment: ';' {.} '\n';

//
// identifier
//
_letter : 'a'-'z' | 'A'-'Z';
_initial: _letter;
_digit  : '0'-'9' ;
_special_subsequent : '.' | '+' | '-' | '!' | '?';
_subsequent: _initial | _digit | _special_subsequent;
_peculiar_identifier: '+' | '-' | '.' '.' '.';
_identifier : _initial { _subsequent } | _peculiar_identifier;
identifier: _identifier;
quoted_identifier: '#' _identifier;

//
// boolean
//
_boolean_t: '#' 't';
_boolean_f: '#' 'f';
boolean_t: _boolean_t;
boolean_f: _boolean_f;

//
// string
//
_string_element: '\\' '"' | . | '\\' '\\';
_string : '"' { _string_element } '"';
string: _string;

//
// number
//
_sign: '+' | '-';
_uint10: _digit { _digit };
_ureal10 : ['.'] _uint10 | _uint10 '.' _digit {_digit};
_number : [_sign] _ureal10;
number: _number;
```

词法元素很简单，运算符也当成 identifier 处理了，万一要扩展也容易。

## 语法定义

gocc 的语法元素定义和词法元素定义差不多。产生式名称要用大写字母开头，后面跟的元素只能是 `token`、语法元素还有字符串字面量。另外就是在每个规则后面可以加上一个 “动作”，用过 flex/bison 的应该知道我说的啥。这个动作是一个表达式，求值后必须是 `interface{}, error` 这样的元组。这个求值结果会被 Parser 返回，所以需要在 Action 里就把 AST 组装好。

另外值得一提的就是语法元素的定义是不支持 `[]`、`{}` 这样的糖的，所以可选就得自己写成 `Opt: Value | empty` ，重复一或多次就得自己写成 `Elements: Element | Elements Element` 诸如此类。

```plaintext
//
// Syntax start here
//

<<
import (
    "github.com/nnnewb/minilang/pkg/ast"
    "github.com/nnnewb/minilang/pkg/bnf/token"
)
>>

//
// value
//
Value
    : identifier            << ast.Identifier(string($0.(*token.Token).Lit)), nil >>
    | quoted_identifier     << ast.NewQuoted(ast.Identifier(string($0.(*token.Token).Lit[1:]))), nil >>
    | boolean_t             << ast.Boolean(true), nil >>
    | boolean_f             << ast.Boolean(false), nil >>
    | number                << ast.NewNumber(string($0.(*token.Token).Lit)) >>
    | string                << ast.String(string($0.(*token.Token).Lit)), nil >>
    | List                  << $0, nil >>
;

//
// list
//
ListElements
    : Value                 << ast.NewListWithInitial($0.(ast.Node)), nil >>
    | ListElements Value    << $0.(*ast.List).Append($1.(ast.Node)), nil >>
;
List
    : "(" ListElements ")"  << $1, nil >>
    | "(" ")"               << ast.NewList(), nil >>
    | "#(" ListElements ")" << ast.NewQuoted($1.(ast.Node)), nil >>
    | "#(" ")"              << ast.NewQuoted(ast.NewList()), nil >>
;
```

s表达式本身就是一个括号括起来的列表，所以语法元素更简单了，直接把词法元素放进去就行。

## 解析和执行

### 执行环境

执行环境就是保存变量（考虑作用域的话还要嵌套）、函数（或者叫 procedure）、解释器内建的函数之类的东西的地方，简单实现成一个 map 就完事了。

```go
type ExecutionEnv struct {
	symbols map[string]Value
	parent  *ExecutionEnv
}

func NewExecutionEnv(parent *ExecutionEnv) *ExecutionEnv {
	return &ExecutionEnv{
		symbols: make(map[string]Value),
		parent:  parent,
	}
}

func (ee *ExecutionEnv) SetValue(name string, val Value) Value {
	old, ok := ee.symbols[name]
	ee.symbols[name] = val
	if ok {
		return old
	}
	return nil
}

func (ee *ExecutionEnv) LookupName(name string) Value {
	if val := ee.LookupLocalName(name); val != nil {
		return val
	}
	return ee.parent.LookupName(name)
}

func (ee *ExecutionEnv) LookupLocalName(name string) Value {
	if val, ok := ee.symbols[name]; ok {
		return val
	}
	return nil
}
```

### 求值

语言定义里（不是 scheme 的语言定义，那个去参考 r4rs/r5rs/r6rs/r7rs，这里指的是我给这个玩具求值器的语言定义），`(a b c)` 这样的列表等于是 `a(b, c)` 这样的函数调用，而原始列表得写成 `#(a b c)`，可以理解成告诉求值器要把给出的表达式当成数据还是代码。

类似的还有`ident`会被求值，在执行环境里寻找对应的变量；`#ident` 求值结果就是标识符`ident`。

求值过程就是简单的做个 type switch，字面量不管，原始列表和标识符返回内容，再然后就是列表当成函数求值。

```go
func (ee *ExecutionEnv) EvaluateList(list List) (Value, error) {
	if len(list) > 0 {
		first, err := ee.Evaluate(list[0])
		if err != nil {
			return nil, err
		}

		if fn, ok := first.(BuiltinFunc); !ok {
			return nil, fmt.Errorf("TypeError: %v(%T) is not callable", first, first)
		} else {
			args := make([]Value, 0, len(list[1:]))
			for _, v := range list[1:] {
				arg, err := ee.Evaluate(v)
				if err != nil {
					return nil, err
				}

				args = append(args, arg)
			}
			return fn(ee, args)
		}
	}
	return nil, nil
}

func (ee *ExecutionEnv) Evaluate(val Value) (Value, error) {
	switch v := val.(type) {
	case *List:
		return ee.EvaluateList(*v)
	case Identifier:
		return ee.LookupName(string(v)), nil
	case *Quoted:
		return v.GetValue().(Value), nil
	default:
		return v, nil
	}
}
```

因为还没写 procdure 的定义，所以直接拿 Builtin 做了类型断言判断是不是可以调用。我寻思传参大概会是个挺麻烦的事情。

### REPL

最后就是解释器本体了，用 `go-prompt` 做了个简单的循环，再加上一点算数函数。

```go
package main

import (
	"fmt"

	"github.com/c-bata/go-prompt"
	"github.com/nnnewb/minilang/internal/builtin"
	"github.com/nnnewb/minilang/internal/environment"
	"github.com/nnnewb/minilang/pkg/ast"
	"github.com/nnnewb/minilang/pkg/bnf/lexer"
	"github.com/nnnewb/minilang/pkg/bnf/parser"
)

func main() {
	for {
		input := prompt.Input(">", func(d prompt.Document) []prompt.Suggest {
			return []prompt.Suggest{}
		})

		if input == ".quit" {
			break
		}

		ee := environment.NewExecutionEnv(nil)
		builtin.RegisterArithmeticBuiltin(ee)
		ee.SetValue("display", environment.BuiltinFunc(func(ee *environment.ExecutionEnv, args []environment.Value) (environment.Value, error) {
			for _, v := range args {
				fmt.Printf("%v", v)
			}
			println()
			return nil, nil
		}))

		lexer := lexer.NewLexer([]byte(input))
		parser := parser.NewParser()
		parseResult, err := parser.Parse(lexer)
		if err != nil {
			fmt.Printf("parse error %v\n", err)
			continue
		}

		val := environment.NewValueFromASTNode(parseResult.(ast.Node))
		evaluated, err := ee.Evaluate(val)
		if err != nil {
			fmt.Printf("evaluation failed, error %v\n", err)
			continue
		}
		fmt.Printf("# (%T) %v\n", evaluated, evaluated)
	}
}
```

最后执行的效果就是这样：

```plaintext
>(display "Hello world!")
"Hello world!"
# (<nil>) <nil>
```

## 总结

s表达式求值不是什么大不了的东西，但 Lisp/Scheme 中体现出的那种 “代码即数据” 的思想还是很有意思的，甚至是很有想象力的。

不管是命令式语言还是函数式语言，代码和数据都是被分开讨论的。“代码”处理“数据”，放在 Lisp 家族里就是 “代码”处理“代码”，有没有联想到 AI ？

好吧，毕竟是上世纪的古董了，现在说起 AI 都是 Python 和神经网络。但不管怎么说吧，Lisp/Scheme 还是挺好玩的对吧？没事可以上 [Racket](https://racket-lang.org/) 官网看看，说不定会喜欢上 Lisp 的奇妙之处呢。
