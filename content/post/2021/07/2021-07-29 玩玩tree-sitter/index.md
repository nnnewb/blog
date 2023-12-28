---
title: 玩玩 tree-sitter
date: 2021-07-29 10:14:36
tags:
- 编译技术
- javascript
- vscode
categories:
- javascript
---



什么是tree-sitter呢？

tree-sitter 是一个 parser-generator，也是一个增量解析库（incremental parsing library）。它可以为源文件构建完整的语法树，并在源文件被编辑时高效地更新。

<!-- more -->

## 快速开始

tree-sitter 本身是一个 parser generator ，使用 javascript 来作为描述语法规则的语言（不像其他，如 yacc 一类的工具，以类似 EBNF 的 DSL 来描述语法规则）。

我们写 tree-sitter 语法规则本质上是类似于写一个 tree-sitter 的语法支持包，可以参考下 [tree-sitter/tree-sitter-go: Go grammar for tree-sitter (github.com)](https://github.com/tree-sitter/tree-sitter-go) 的项目结构。

废话不多说，先写个简单的 demo 跑起来。

```bash
mkdir tree-sitter-hello && cd tree-sitter-hello
npm init
npm i --save nan
npm i --save-dev tree-sitter-cli
```

初始化好项目目录，在 package.json 里写个简单的命令，方便之后用。

```json
{
    "scripts":{
        "test": "tree-sitter generate && tree-sitter parse test.txt"
    }
}
```

现在开始干正事儿，创建一个 grammar.js

```js
module.exports = grammar({
    name: 'hello',
    rules: {
        source_file: $ => repeat($.word), // 非终结符，0或更多的 word
        word: $ => /\w+/ // 非常简单的终结符，表示一个词，可以是数字字母下划线组成
    }
})
```

再写一个 test.txt 作为输入

```
amazing tree sitter
```

最后运行。

```bash
npm run test
```

输出结果

```

> tree-sitter-hello@0.1.0 test
> tree-sitter generate && tree-sitter parse test.txt

(source_file [0, 0] - [1, 0]
  (word [0, 0] - [0, 7])
  (word [0, 8] - [0, 12])
  (word [0, 13] - [0, 19]))
```

就是这样！

## 规则 DSL

所有规则都用这种格式编写

```js
rule_name1: $ => /terminal-symbol/,
rule_name2: $ => seq('non', 'terminal', 'symbol')
```

正则表达式或字符串表示终结符，规则函数表示非终结符（token函数是例外）

一些函数来标识 ENBF 里出现的规则：

- `repeat` 就是重复0或多次，类似 EBNF 的 `{ }` 含义
- `repeat1` 至少出现一次，可以重复多次，类似 EBNF 的 ` SYM { SYM }` 这样的形式
- `optional` 可选，类似 EBNF 的 `[ ]` 含义
- `choice` 多选一，类似 EBNF 的 `|` 含义
- `seq` 序列，表示前后顺序，在 EBNF 里就是符号出现的顺序
- `token` ，把一个复杂规则合并成一个 token，一般是难以用一个正则表达式解决的终结符会用 `token(choice(/hex/,/octal/,/decimals/))` 这种形式编写。

还有其他的，用于设置左右联结性优先级什么的，就不多介绍了。可以自己看tree-sitter的文档。

## 更复杂一点的例子

贴一个参考 protocol buffer 3 的 spec 写出来的 grammar.js

```js
module.exports = grammar({
  name: 'protobuf',
  extras: ($) => [$.comment, /\s/],
  rules: {
    // top
    source_file: ($) =>
      seq($.syntax, repeat(choice($.import, $.package, $.option, $.emptyStatement, $.enum, $.message, $.service))),

    // comment
    comment: ($) => token(seq('//', /.*/)),

    // syntax
    syntax: ($) => seq('syntax', '=', /"proto3"/, ';'),

    // package
    package: ($) => seq('package', $.fullIdent, ';'),

    // imports
    import: ($) => seq('import', $.strLit, ';'),

    // option
    option: ($) => seq('option', $.optionName, '=', $.constant, ';'),
    optionName: ($) => choice(seq('(', $.fullIdent, ')'), $.fullIdent),

    // enum
    enum: ($) => seq('enum', $.enumName, $.enumBody),
    enumBody: ($) => seq('{', repeat(choice($.option, $.enumField, $.emptyStatement)), '}'),
    enumField: ($) =>
      seq(
        $.ident,
        '=',
        optional('-'),
        $.intLit,
        optional(seq('[', $.enumValueOption, repeat(seq(',', $.enumValueOption)), ']')),
        ';'
      ),
    enumValueOption: ($) => seq($.optionName, '=', $.constant),

    // message
    message: ($) => seq('message', $.messageName, $.messageBody),
    messageBody: ($) =>
      seq(
        '{',
        repeat(choice($.field, $.enum, $.message, $.option, $.oneof, $.mapField, $.reserved, $.emptyStatement)),
        '}'
      ),

    // service
    service: ($) => seq('service', $.serviceName, '{', repeat(choice($.option, $.rpc, $.emptyStatement)), '}'),
    rpc: ($) =>
      seq(
        'rpc',
        $.rpcName,
        '(',
        optional('stream'),
        $.enumMessageType,
        ')',
        'returns',
        '(',
        optional('stream'),
        $.enumMessageType,
        ')',
        choice(seq('{', repeat(choice($.option, $.emptyStatement)), '}'), ';')
      ),

    // field and inline option
    field: ($) =>
      seq(optional('repeated'), $.type, $.fieldName, '=', $.fieldNumber, optional(seq('[', $.fieldOptions, ']')), ';'),
    fieldOptions: ($) => seq($.fieldOption, repeat(seq(',', $.fieldOption))),
    fieldOption: ($) => seq($.optionName, '=', $.constant),

    // oneof
    oneof: ($) => seq('oneof', $.oneofName, '{', repeat(choice($.option, $.oneofField, $.emptyStatement)), '}'),
    oneofField: ($) => seq($.type, $.fieldName, '=', $.fieldNumber, optional(seq('[', $.fieldOptions, ']')), ';'),

    // map
    mapField: ($) =>
      seq(
        'map',
        '<',
        $.keyType,
        ',',
        $.type,
        '>',
        $.mapName,
        '=',
        $.fieldNumber,
        optional(seq('[', $.fieldOptions, ']')),
        ';'
      ),
    keyType: ($) =>
      choice(
        'int32',
        'int64',
        'uint32',
        'uint64',
        'sint32',
        'sint64',
        'fixed32',
        'fixed64',
        'sfixed32',
        'sfixed64',
        'bool',
        'string'
      ),

    // reserved
    reserved: ($) => seq('reserved', choice($.ranges, $.fieldNames)),
    ranges: ($) => seq($.range, repeat(seq(',', $.range))),
    range: ($) => seq($.intLit, optional(seq('to', choice($.intLit, 'max')))),
    fieldNames: ($) => seq($.fieldName, repeat(seq(',', $.fieldName))),

    // integer literals
    intLit: ($) => /(\d\d*|0[0-7]*|0[xX][\da-fA-F]*)/,

    // floating-point literals
    floatLit: ($) => choice(/\d\.\d*([eE][+-]\d*)?/, /\d*[eE][+-]\d*/, /\.\d*[eE][+-]\d*/, 'inf', 'nan'),

    // boolean literals
    boolLit: ($) => /(true|false)/,

    // string literals
    strLit: ($) =>
      choice(
        seq('"', /([^"\n\\]|\\[xX][\da-fA-F]{2}|\\[0-7]{3}|\\[abfnrtv\\'"])*/, '"'),
        seq("'", /([^'\n\\]|\\[xX][\da-fA-F]{2}|\\[0-7]{3}|\\[abfnrtv\\'"])*/, "'")
      ),

    // built-in field type
    type: ($) =>
      choice(
        'double',
        'float',
        'int32',
        'int64',
        'uint32',
        'uint64',
        'sint32',
        'sint64',
        'fixed32',
        'fixed64',
        'sfixed32',
        'sfixed64',
        'bool',
        'string',
        'bytes',
        $.enumMessageType
      ),
    fieldNumber: ($) => $.intLit,

    // empty statement
    emptyStatement: ($) => ';',

    // constant
    constant: ($) =>
      choice(
        $.fullIdent,
        seq(optional(/[+-]/), $.intLit),
        seq(optional(/[+-]/), $.floatLit),
        $.strLit,
        $.boolLit,
        $.msgLit
      ),
    msgLit: ($) => seq('{', repeat(seq($.fieldName, ':', $.constant)), '}'),

    // identifier
    ident: ($) => /[a-zA-Z_]\w*/,
    fullIdent: ($) => seq($.ident, repeat(seq('.', $.ident))),
    messageName: ($) => $.ident,
    mapName: ($) => $.ident,
    enumName: ($) => $.ident,
    fieldName: ($) => $.ident,
    oneofName: ($) => $.ident,
    serviceName: ($) => $.ident,
    rpcName: ($) => $.ident,
    enumMessageType: ($) => seq(optional('.'), repeat(seq($.ident, '.')), $.messageName),
  },
});
```

## 编译和使用

生成的是c代码，默认是编译成机器码，和cpu指令集架构强相关。有很多语言提供了基于 C 接口的绑定。

不过现在也支持编译成 wasm，只需要用下面的命令

```bash
tree-sitter build-wasm
```

加载方式也是用 `Language.load` ，不过只有 web-tree-sitter 能加载。web-tree-sitter 可以用 `npm i --save tree-sitter` 来安装。

于是写个 main.js ，加载代码如下

```js
const Parser = require("web-tree-sitter");
Parser.init().then(() => {
  Parser.Language.load("tree-sitter-hello.wasm").then((lang) => {
    const parser = new Parser();
    parser.setLanguage(lang);
    const ast = parser.parse("amazing tree parser");
    console.log(ast.rootNode.toString());
  });
});
```

 最终输出是

```
(source_file (word) (word) (word))
```

## 编辑和更新

这个还没搞明白。

回头参考下别的 repo 的代码，看看别人是怎么做语法树更新的。

