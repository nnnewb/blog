---
title: 自娱自乐 CrackMe-1
slug: crackme-01
date: 2021-09-10 09:49:00
categories:
- 逆向
tags:
- 汇编
- 逆向
---

## 前言

总之得有个前言。从前有个老和尚（不是，掉光了头发的攻城狮），......

以上略，于是作为萌新含量110%的萌新，出于练手、熟悉下反汇编调试的环境之类的目的，还是自己写crackme来把玩吧。

## CM01 介绍

于是这个 CrackMe 就叫 CM01 好了，命令行无界面。适合差不多对这些东西懂个大概或者打算学习的萌新：

- 反汇编/调试工具
- 寄存器（主要是 ebp、esp、eip、eax）
- 函数调用（cdecl）
- 栈/栈帧
- 内存模型和寻址

## CM01 源码

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

size_t getline(char **lineptr, size_t *n, FILE *stream) {
  char *bufptr = NULL;
  char *p = bufptr;
  size_t size;
  int c;

  if (lineptr == NULL) {
    return -1;
  }
  if (stream == NULL) {
    return -1;
  }
  if (n == NULL) {
    return -1;
  }
  bufptr = *lineptr;
  size = *n;

  c = fgetc(stream);
  if (c == EOF) {
    return -1;
  }
  if (bufptr == NULL) {
    bufptr = malloc(128);
    if (bufptr == NULL) {
      return -1;
    }
    size = 128;
  }
  p = bufptr;
  while (c != EOF) {
    if ((p - bufptr) > (size - 1)) {
      size = size + 128;
      bufptr = realloc(bufptr, size);
      if (bufptr == NULL) {
        return -1;
      }
    }
    *p++ = c;
    if (c == '\n') {
      break;
    }
    c = fgetc(stream);
  }

  *p++ = '\0';
  *lineptr = bufptr;
  *n = size;

  return p - bufptr - 1;
}

int main() {
  const char *pwd = "secret";
  char *line = NULL;
  size_t len = 0;
  long int linesize = 0;

  while (1) {
    printf("password:");
    linesize = getline(&line, &len, stdin);
    int rc = strncmp(line, pwd, 6);
    if (rc == 0) {
      printf("Good job!\n");
      break;
    } else {
      printf("wrong pwd!\n");
    }
  }
  return 0;
}
```

编译工具链：

- 因为VC++对单纯C的支持比较垃圾，所以用LLVM（Clang）-12.0.1，Clang

编译指令

```shell
clang cm01.c -o cm01-easy.exe -m32 -O0
clang cm01.c -o cm01-normal.exe -m32 -O1
clang cm01.c -o cm01-hard.exe -m32 -O2
```

## 观察

假装没看到源码，先观察下程序的行为，确定目标。

```plain
weakptr in assembly-play ❯ .\cm01-easy.exe
password:password?
wrong pwd!
password:asdf
wrong pwd!
password:wrong pwd!
password:
```

一个 *password:* 提示符，随便输入了点什么会提示 *wrong pwd!* 。

确定目标是找出正确的密码。

## 静态分析

### 思路

在逆向中有个说法叫*“关键跳转”*，如分析固定密码，字符串比较后跳转成功或跳转失败就是关键跳。对于简单的问题，找到关键跳即可破局。

### 反汇编 - Easy

Easy难度下，`-O0`参数关闭了编译器优化，生成的汇编代码非常死板，基本能直接对照到C源码上。

直接拿IDA打开。

![image-20210912172521751](image/crackme-01/cm01-easy-1.png)

直接跳到了`main`函数。接着看IDA汇编窗口中的的细节。

![image-20210912173539972](image/crackme-01/cm01-easy-2.png)

IDA反汇编界面是包含一些伪代码的，有助于分析。

左侧有长条和箭头的部分是控制流示意，箭头指的就是跳转方向。

越过伪代码的部分，就能看到函数体开头例行公事的部分了。随后的便是函数体代码。

具体看函数体前，先了解下IDA还提供了另一种控制流可视化的视图，可以极大帮助对函数逻辑的分析。

在汇编视图里右键，选择 Graph View，即可进入控制流视图。

![image-20210912174233891](image/crackme-01/cm01-easy-3.png)

在图片左下角的是视图的全览，原本的汇编文本变成了图中箭头连接的小汇编代码块，箭头指示了跳转的方向。

在这个视图可以很清楚地看到所谓的关键跳：

![image-20210912174738919](image/crackme-01/cm01-easy-4.png)

`_strncmp`是经过了 name mangling 的 c 标准库函数`strncmp`，函数如名字所示，用途就是比较字符串。

又根据`cdecl`调用约定，函数参数通过栈传递，参数从右往左压栈。我们看这个`call`指令前的三句`mov`。

```asm
mov     [esp+24h+Ix], ecx ; Str1
mov     [esp+24h+Str2], eax ; Str2
mov     [esp+24h+MaxCount], 6 ; MaxCount
```

需要注意的是没有用`push`指令，所以三个`mov`在栈上的顺序要根据偏移算。我们偷个懒直接看`strncmp`函数的签名就行，IDA也分析出了压栈的地址在注释里。往上看，看看`ecx`和`eax`又是哪儿来的。

```asm
mov     eax, [ebp+var_8]
mov     ecx, [ebp+Str1]
```

再看`ebp+var_8`和`ebp+str1`又是什么。

```asm
lea     eax, aSecret    ; "secret"
mov     [ebp+var_8], eax
```

所以有一个参数是字符串 `"secret"`，作为关键跳前 `_strncmp` 的参数。

让我们尝试一下。

![image-20210912181959230](image/crackme-01/cm01-easy-7.png)

成功完成。

### 反汇编 - Normal

接下来看使用`-O1`编译，开启了部分编译器优化的版本。

![image-20210912183427553](image/crackme-01/cm01-normal-1.png)

可以看到，因为编译器优化的缘故，原本清晰的分支变成了一个仅有一个循环。

还是先找到关键跳，肉眼过一遍循环中的函数调用，`sub_401180`从参数看应该是一个往终端打印字符串的函数，忽略。`___acrt_iob_func`意义不明也忽略。下一个`sub_401000`依然有点意义不明，先跳过。再往下就看到了老熟人了，`_strncmp`，`"secret"`参数更是直接用一个push给压栈了，分析到此结束？

不过还有一个问题没解决：失败的提示我们看到了，成功的跳转在哪儿呢？

从`call _strncmp`开始往下看。

```asm
call    _strncmp ; 调用，cdecl约定下，返回值在 eax
add     esp, 0Ch ; 清栈
mov     esi, eax ; 函数返回值存入 esi
test    eax, eax ; TEST 指令把操作数按位与并设置标志位，如果 eax 是 0 则 ZF 会设置成 1，否则就是 0。
mov     eax, offset aWrongPwd ; eax = "wrong pwd!\n"
; ebp 被设置为了字符串 "Good job!\n"
; cmovz 或者说 cmov* 系列的函数用后缀的单个字符表示用哪个标志位来决定是否mov，比如cmovz就是用ZF标志位决定是否执行mov。
cmovz   eax, ebp 
push    eax ; 如果 strncmp 返回 0 则是 Good job!\n ，反则 wrong pwd!\n
call    sub_401180 ; 调用一个输出字符串的函数
```

用伪代码来表示，就是

```python
print("Good job!\n" if compare_result == 0 else "wrong pwd!\n")
```

### 反汇编 - Hard

Hard启用了`-O2`，也就是开启了大部分编译器优化。用IDA打开。

![image-20210912185949657](image/crackme-01/cm01-hard-1.png)

因为编译器十分聪明地把一些函数给内联编译进了 main 函数，现在 main 函数的控制流已经乱的一批。挨个读下去虽然还可行，但实在费神费力。

不过在这个条件下依然还有解决办法：我们可以通过错误或成功的提示字符串找关键跳。

已知错误时会输出"wrong pwd!"，我们在IDA找到字符串视图。

![image-20210912190657661](image/crackme-01/cm01-hard-2.png)

然后在视图中找到字符串。

![image-20210912190827657](image/crackme-01/cm01-hard-3.png)

其实就是在内存数据段（Data Segment）或者PE的数据节（Data Section）中的字符串啦，一般手写的字符串字面量都会直接编译到这里。

在我们要找的字符串上双击，就会跳到汇编视图中的字符串位置。

![image-20210912191125747](image/crackme-01/cm01-hard-4.png)

然后再双击图中位置。

![image-20210912191344967](image/crackme-01/cm01-hard-5.png)

即可跳转到引用。

![image-20210912191435672](image/crackme-01/cm01-hard-6.png)

接着看跳转到的上下文，又变成了十分熟悉的正确错误分支。往前找到 `_strncmp`的参数。

```asm
push    6
push    offset Str2     ; "secret"
push    edx             ; Str1
mov     ebp, edx
call    _strncmp
```

也就是 `strncmp(edx,"secret",6)`，密钥就是 `"secret"`没错了。

## 总结

这个 CrackMe （以后也许还有）的主要用途是学习逆向和汇编的基础知识，巩固记忆，学习和熟悉工具。所以尽可能去除干扰项，只保留想要巩固学习的部分，看起来很傻，基本没啥挑战性。

目前能找到很多 Delphi 和 VB 编写的 CrackMe，Delphi 现在搜搜还能看到些 *Delphi still alive* 的文章，不过确实比较少见了吧。提到学 GUI 编程，不是推荐 C++/Qt 就是 .Net 全家桶。VB 更是早已完蛋（不是VB.Net），老实说这些 CrackMe 不知道转了几手，还能玩是还能玩，虽然但是吧，总之对我还是略难，看别人的 CrackMe 题解也挺迷茫。

不过自己会编程就好了嘛！
