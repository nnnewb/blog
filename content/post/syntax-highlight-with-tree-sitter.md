---
title: 用 tree-sitter 写一个代码高亮
date: 2021-08-03 15:52:21
categories: ["javascript"]
tags:
  - javascript
  - 编译技术
  - vscode
---

这次用 tree-sitter 写一个简单的代码高亮。

<!-- more -->

## 前言

我寻思代码高亮是什么应该没啥可解释的，也有叫“语法高亮”，总之都是一个意思。就是给编辑器里的代码涂上颜色，便于阅读。

一般来说，简单的代码高亮只需要正则表达式就能搞定（比如说关键字高亮，Camel Case 标识符高亮等），不过正则表达式来实现高亮还是有很大的局限性。

举例来说，当我把函数当参数传给另一个函数的时候——

```javascript
function f() {}

function higher(fn) {
  return () => fn() != 0;
}

higher(f);
```

在 `higher(f)` 这一行中的 `f` 不会以函数名的颜色标出。这就引出了一种新基于语义的代码高亮，让编辑器真正“认识”你的代码，并提供更聪明的提示。

## 开始

还是在 vscode 折腾。

先创建一个 vscode 插件项目，用 `yo code` 完成。

然后编辑 `package.json` ，添加你的语言和插件的激活事件。

```json
{
  "activationEvents": ["onLanguage:proto"],
  "contributes": {
    "languages": [
      {
        "id": "proto",
        "extensions": [".proto"]
      }
    ]
  }
}
```

然后修改 `src/extension.ts`，去掉默认创建的 hello world 代码，留一个 `console.log`，然后 F5 启动，打开一个 `.proto` 文件，检查插件是否已经激活。

```typescript
// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
import * as vscode from "vscode";

// this method is called when your extension is activated
// your extension is activated the very first time the command is executed
export function activate(context: vscode.ExtensionContext) {
  console.log("activated!");
}

// this method is called when your extension is deactivated
export function deactivate() {}
```

## 创建和注册 DocumentSemanticTokensProvider

创建文件 `src/providers/SemanticTokensProvider.ts` ，编写一个类，实现接口 `vscode.DocumentSemanticTokensProvider`。

```typescript
import * as vscode from "vscode";
const Parser = require("web-tree-sitter");

export default class SemanticTokenProvider
  implements vscode.DocumentSemanticTokensProvider
{
  constructor(public legend: vscode.SemanticTokensLegend) {
    Parser.init().then(() => {
      Parser.Language.load(
        path.resolve(__dirname, "../../assets/tree-sitter-proto.wasm")
      ).then((lang) => {
        this.parser = new Parser();
        this.parser.setLanguage(lang);
      });
    });
  }

  onDidChangeSemanticTokens?: vscode.Event<void> | undefined;

  provideDocumentSemanticTokens(
    document: vscode.TextDocument,
    token: vscode.CancellationToken
  ): vscode.ProviderResult<vscode.SemanticTokens> {
    throw new Error("Not implemented");
  }
}
```

再到 `src/extension.ts` 里注册。

```ts
export function activate(context: vscode.ExtensionContext) {
  console.log("activated!");

  // register semantic tokens provider
  const tokenTypes = [
    "type",
    "enum",
    "class",
    "function",
    "comment",
    "string",
    "number",
    "keyword",
    "parameter",
  ];
  const modifiers = ["definition", "deprecated", "documentation"];
  const selector: vscode.DocumentSelector = {
    language: "proto",
    scheme: "file",
  };
  const legend = new vscode.SemanticTokensLegend(tokenTypes, modifiers);
  const provider = new SemanticTokenProvider(legend);

  context.subscriptions.push(
    vscode.languages.registerDocumentSemanticTokensProvider(
      selector,
      provider,
      legend
    )
  );
}
```

这个 `tree-sitter-proto.wasm` 是编译好的语法定义，参考[另一篇文章](./play-with-tree-sitter.md)。

这样一来，`new SemanticTokenProvider(legend)` 时就会初始化 parser 了。

## 实现

先写个简单的 `provideDocumentSemanticTokens` 实现。

```typescript
class SemanticTokenProvider {
  provideDocumentSemanticTokens(
    document: vscode.TextDocument,
    token: vscode.CancellationToken
  ): vscode.ProviderResult<vscode.SemanticTokens> {
    const tree = this.parser?.parse(document.getText());
    const query: Parser.Query = this.parser
      ?.getLanguage()
      .query('("message") @keyword');
    const captures = query.captures(tree!.rootNode);

    const tokenBuilder = new vscode.SemanticTokensBuilder(this.legend);
    for (const capture of captures) {
      tokenBuilder.push(
        new vscode.Range(
          new vscode.Position(
            capture.node.startPosition.row,
            capture.node.startPosition.column
          ),
          new vscode.Position(
            capture.node.endPosition.row,
            capture.node.endPosition.column
          )
        ),
        capture.name
      );
    }

    const tokens = tokenBuilder.build();
    return Promise.resolve(tokens);
  }
}
```

最核心的部分就是 `getLanguage().query()` 了，这里用了 tree-sitter 的查询语言 DSL 实现快速从语法树里提取对应的节点。

放个[查询语言的文档](https://tree-sitter.github.io/tree-sitter/using-parsers#query-syntax)，再简要介绍下。

> A query consists of one or more patterns, where each pattern is an S-expression that matches a certain set of nodes in a syntax tree.

本质上查询语言是个模式匹配工具，以 s-expression 作为模式语言。例如下面的查询。

```
(number)
```

就是查询 ast 里所有的 number 节点。而 number 节点的定义在 tree-sitter 项目语法定义 `grammar.js` 中给出。

再看复杂一点的查询：

```
(binary_expression
    (number)
    (number)
)
```

就是查询语法树中的 包含两个 number 子节点的 binary_expression 节点，不限定 number 节点的位置，只要是子节点就行。

语法树的结构可以参考 `tree-sitter parse` 命令的输出。

当然也可以以子节点的值为条件来查询。

```
(binary_expression
    left:(number)
)
```

再看如何捕获查询结果。

```
(function
    name: (identifier) @function_name
)
```

用 `@` 开头的标识符指定捕获的名称，通过 `query.captures()` 即可完成捕获，返回 `{name: string, node: Node}` 这样子的对象的列表。

这样一来，上面的代码就很容易理解了。

```ts
const query: Parser.Query = this.parser
  ?.getLanguage()
  .query('("message") @keyword');
const captures = query.captures(tree!.rootNode);
```

这两句话查询出了语法树里所有的 `message` 关键字

```ts
const tokenBuilder = new vscode.SemanticTokensBuilder(this.legend);
for (const capture of captures) {
  tokenBuilder.push(
    new vscode.Range(
      new vscode.Position(
        capture.node.startPosition.row,
        capture.node.startPosition.column
      ),
      new vscode.Position(
        capture.node.endPosition.row,
        capture.node.endPosition.column
      )
    ),
    capture.name
  );
}
```

这一段循环将捕获的结果构造出高亮 token，注意这里用了 `capture.name` 作为标识符的类型，也就是上面的 query 里指定的 `keyword` 。

最终，将分词的结果返回出去。

```ts
const tokens = tokenBuilder.build();
return Promise.resolve(tokens);
```

F5 运行即可看到源码中所有 `message` 都被标上了关键字的颜色。
