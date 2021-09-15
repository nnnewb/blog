---
title: 自娱自乐 crackme-02
slug: crackme-02
date: 2021-09-15 15:43:00
categories:
- 逆向
tags:
- 汇编
- 逆向
---

## 得有个前言

总之上一个 crackme-01 还过得去，稍微加强一点，把密码隐藏起来，不要随便被看到。

## 0x01 源码

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

size_t r_trim(char *str, size_t len) {
  size_t slen = strnlen(str, len);
  for (size_t i = slen - 1; i >= 0; i++) {
    if (str[i] == ' ' || str[i] == '\n' || str[i] == '\r') {
      str[i] = '\0';
    } else {
      break;
    }
  }
  return strnlen(str, len);
}

char *calculate(char *username, const size_t username_len) {
  // 初始化固定8字节计算密钥的空间
  const size_t input_buf_len = 8;
  char *input_buf = malloc(input_buf_len);
  for (size_t i = 0; i < input_buf_len; i++) {
    input_buf[i] = 0x52 + i;
  }
  // 用用户输入替换初始化的数据
  memcpy_s(input_buf, input_buf_len, username, username_len);

  // 异或处理
  for (size_t i = 0; i < input_buf_len; i++) {
    input_buf[i] ^= 0x25;
  }

  // 初始化 Hex 输出
  const size_t output_buf_len = 17;
  char *output_buf = malloc(output_buf_len);

  // 转为可读字符串
  for (size_t i = 0; i < input_buf_len; i++) {
    sprintf(&output_buf[i * 2], "%02x", input_buf[i]);
  }

  output_buf[16] = 0;
  free(input_buf);
  return output_buf;
}

int main() {
  while (1) {
    char *username = NULL;
    size_t username_len = 0;
    char *serial = NULL;
    size_t serial_len = 0;
    size_t linesize = 0;

    printf("username:");
    linesize = getline(&username, &username_len, stdin);
    username_len = r_trim(username, linesize);
    if (username_len > 8) {
      free(username);
      puts("username less than 8 letter");
      continue;
    } else if (username_len == 0) {
      free(username);
      continue;
    }

    printf("serial:");
    linesize = getline(&serial, &serial_len, stdin);
    serial_len = r_trim(serial, linesize);
    if (serial_len != 16) {
      free(username);
      free(serial);
      puts("serial has 16 letters");
      continue;
    }

    char *correct = calculate(username, username_len);
    int rc = strncmp(serial, correct, 16);
    if (rc == 0) {
      free(correct);
      puts("Good job!");
      break;
    } else {
      puts("wrong pwd!");
    }
    free(username);
    free(serial);
    free(correct);
  }
  return 0;
}
```

编译方式是

```batch
clang main.c -o cm02-easy.exe -Wall -m32 -O0
clang main.c -o cm02-normal.exe -Wall -m32 -O1
clang main.c -o cm02-hard.exe -Wall -m32 -O2
```

## 0x02 观察

启动后观察行为（不截图了。）

```plaintext
weakptr in cm02 ❯ .\cm02-easy.exe
username:abc
serial:123456
serial 长度为16
username:abc
serial:123456789012345 
wrong pwd!
username:
serial:
serial 长度为16
username:abc
serial:aaaaaaaaaaaaaaa
wrong pwd!
```

这次的目标是：

1. 得到某个用户名对应的序列号（`serial`）。
2. 破解，总是正确或对任何输入都提示正确。
3. 注册机。

## 0x03 静态分析 - easy

### 3.1 主循环

在公司没IDA，用 [Cutter](image/crackme-02/https://cutter.re/) 打开，在上方输入框输入 `main` 跳转到 `main` 函数。

![image-20210914114426600](image/crackme-02/cm02-easy-1.png)

然后点击 *图表（main）* 进入类似 IDA 的控制流视图。

![image-20210914114547128](image/crackme-02/cm02-easy-2.png)

之后就能看到下面的控制流了。

![](image/crackme-02/cm02-easy-3.png)

easy难度下没有开启任何编译器优化，控制流和原始代码能直接对应上。瞧着困难很多对吧？

先简单扫一眼，会发现很多分支直接跳回了`0x0040139d`，也就是从上往下数第二个代码块，基本每个跳转都是下一个块或跳回这个块。按照 [cm01](https://nnnewb.github.io/blog/p/crackme-01/)的经验，我们先找到关键的一跳。可以直接搜索字符串引用（`wrong pwd!`），也可以逐个代码块看下去。

很快，右下角的关键跳出现在眼前。

![image-20210914152834262](image/crackme-02/cm02-easy-4.png)

接着回头看跳转条件。

![image-20210914153728179](image/crackme-02/cm02-easy-5.png)

虽然没有名字，但`fcn.00403ef4` 是老熟人了。三个参数，`ecx`、`eax`、`0x10`，返回结果和`0`做比较，`jne`条件跳转。

- `cmp`指令，操作数相减（`dest`-`src`），结果存入标志位 `SF`和`ZF`。
  - 结果是负数（`dest`<`src`），`SF`也就是结果符号位设置为1。
  - 结果是正数（`dest`>`src`），`SF`也就是结果符号位设置为0。
  - 结果是0（`dest`=`src`），`ZF`设置为1。
- `jne`或`jnz`指令，非零跳转。`ZF`标志位为`1`时跳转。

猜测这个函数应该是`strncmp`。继续往回看参数是怎么来的。

![image-20210914155544252](image/crackme-02/cm02-easy-6.png)

`eax`来自`sub.02x_40298c`这个函数，后面两个脱裤子放屁的`mov`忽略。`ecx`则来来自`mov ecx,dword [ebp-10h]`这一行。

先不着急分析函数，继续往回找，找到`[ebp-10h]`的来源。

![image-20210914161814604](image/crackme-02/cm02-easy-7.png)

在入口点附近，看到`[ebp-10]`被初始化成了0。

因为没有很明确的路径，手动计算栈上偏移又非常麻烦，这里本应该掏出调试器——但出于学习练手的目的，还是先尝试计算下。首先回顾下简化的栈内存布局，从上往下增长，如图。

![stack-layout](image/crackme-02/cm02-easy-8.png)

接下来从`mov ebp,esp`开始，往下列出所有函数调用，捋一捋逻辑。

![image-20210914214920437](image/crackme-02/cm02-easy-9.png)

第一个框，`[esp+2ch+Ix]` 计算结果是 `[esp]`，也就是栈顶，栈顶设置为字符串 `username:`，接着调用一个未知函数。从参数判断我们先认为是一个输出字符串的函数。

再看第二个框，`acrt_iob_func`，百度一下就会发现，`__acrt_iob_func`函数是定义于 c 运行库里的函数，作用是返回 `stdin/stdout/stderr` 。栈顶设置为0，所以获得的是 `stdin`。

再看第三个框，`edx`和`ecx`赋值为栈上两个变量的地址，再为参数。按顺序就是`f(edx,ecx,stdin)`。暂时不明。函数返回值被赋值回了`[ebp-18h]`。

第四个框，从第三个框得到的返回值被当参数传给一个未知函数。`f([ebp-8h], [ebp-18h])`，返回值被赋值回 `[ebp-0Ch]`。

结合最后的 `cmp` 和 `jbe` 指令分析，人肉反编译后用伪代码表示，就是下面这样。`jbe`指令只在`cmp`左操作数小于等于右操作数时执行跳转（`CF`标志位和`ZF`标志位其中一个为1时）。

```python
var var_8 # 偏移值 ebp-8h
var var_0C # 偏移值 ebp-0Ch
var var_18 # 偏移值 ebp-18h

print("username:")
var_18 = unknown_func1(&var_8,&var_0c,stdin)
var_0c = unknown_func2(var_8, var_18)
if var_0c <= 8:
    ... # jbe 跳转执行
```

![image-20210914223919137](image/crackme-02/cm02-easy-10.png)

可以看出，当 `var_0c` 小于 8 时，提示 `username less than 8 letter` 。因此可以确定 `[ebp-0Ch]` 这个变量就是 `username` 字符串的长度，上一个函数会计算字符串长度返回。我们再根据这个发现修改下伪代码。

```python
var var_8 # 偏移值 ebp-8h
var username_len # 偏移值 ebp-0Ch
var var_18 # 偏移值 ebp-18h

print("username:")
var_18 = unknown_func1(&var_8,&username_len,stdin) # var_8 可能是 username 指针
username_len = unknown_func2(var_8, var_18) # 计算字符串长度
if username_len <= 8:
    ... # jbe 跳转执行
else:
    # jmp 到开头

```

第一个未知函数看起来已经呼之欲出了，`stdin`和`&username_len`作为参数，`var_8` 有极大可能就是`username`字符串指针。不过在进入调试器前，还不能马上下结论，继续看正确跳转的代码。

```asm
cmp [ebp-0Ch], 0
jnz ...
```

这次是比较用户名长度和0，非0跳转。

![image-20210914224625891](image/crackme-02/cm02-easy-11.png)

可以看到为零时，经过一个未知函数 `sub_4036FC(var_8)` 后，跳回开头。

继续看正确流程，`jmp $+5` ，`$` 表示当前正在执行的代码在代码段内的偏移量，+5就是从当前代码开始往后跳过5个字节，我们直接看IDA分析好的跳转位置。

![image-20210914225052452](image/crackme-02/cm02-easy-12.png)

又是非常熟悉的代码，和读取 `username` 的分析方式相同，以相同的顺序调用相同的函数，可以得到`var_14`是`serial_len`，`Str1`可能是`serial`字符串指针。不做重复分析，继续往下看。

![image-20210914225322787](image/crackme-02/cm02-easy-13.png)

右边的代码块是关于长度的判断，分析方法不再重复。左侧代码就是我们的关键跳转了，其中出现两个函数调用。

```asm
mov     eax, [ebp+var_C]
mov     ecx, [ebp+Block]
mov     [esp+2Ch+Ix], ecx ; void *
mov     [esp+2Ch+Str2], eax ; size_t
call    sub_401250
mov     [ebp+var_1C], eax
```

`var_c`先前被判断是`username_len`，`Block`就是`var_8`，先前被怀疑是用户键入的用户名字符串指针。未知函数的返回值保存在 `[ebp-1ch]`中。

这个`1c`在随后的代码中立刻被用到。

```asm
mov     eax, [ebp+var_1C]
mov     ecx, [ebp+Str1]
mov     [esp+2Ch+Ix], ecx ; Str1
mov     [esp+2Ch+Str2], eax ; Str2
mov     [esp+2Ch+MaxCount], 10h ; MaxCount
call    _strncmp
mov     [ebp+var_20], eax
```

`Str1`在`serial`输入这一步被怀疑是用户输入的序列号字符串指针，它和上一个函数调用返回的`var_1c`被作为参数传递给`strncmp`，字符串长度最大16字节。由此可见，`var_1c`基本可以确定是正确序列号的指针，之前的未知函数可能就是生成序列号的函数。

下一步分析序列号生成函数。

### 3.2 生成序列号

先看下控制流全览，能依稀分辨出三个循环。

![generate](image/crackme-02/cm02-easy-14.png)

自动分析出的变量表

```asm
; var uint32_t var_1ch @ ebp-0x1c
; var int32_t var_18h @ ebp-0x18
; var int32_t var_14h @ ebp-0x14
; var uint32_t var_10h @ ebp-0x10
; var uint32_t var_ch @ ebp-0xc
; var int32_t var_8h @ ebp-0x8
; var int32_t var_4h @ ebp-0x4
; arg uint32_t arg_8h @ ebp+0x8
; arg int32_t arg_ch @ ebp+0xc
; var int32_t var_sp_4h @ esp+0x4
; var int32_t var_sp_8h @ esp+0x8
; var int32_t var_sp_ch @ esp+0xc
```

先看循环外的代码，简单按用途划一下分隔线。

```asm
0x004071f0      push    ebp
0x004071f1      mov     ebp, esp
0x004071f3      sub     esp, 0x2c
; ---
0x004071f6      mov     eax, dword [arg_ch]
0x004071f9      mov     eax, dword [arg_8h]
; ---
0x004071fc      mov     dword [var_4h], 8
; ---
0x00407203      mov     dword [esp], 8
0x0040720a      call    fcn.00401302
0x0040720f      mov     dword [var_8h], eax
; ---
0x00407212      mov     dword [var_ch], 0
```

开头是惯例的两句栈帧准备动作，随后开辟 0x2c 大小的栈空间。

两个没用的 `mov eax,...`，之后是`[ebp-4h]`设置为8，再把8作为参数调用了一个未知函数，返回值赋值给`[ebp-8h]`，再初始化`[ebp-ch]`为 0。伪代码表示就是下面这样。

```c
int var_4h, var_8h， var_ch; // ebp-4h, ebp-8h, ebp-ch
var_4h = 0x8;
var_8h = unknown_func(0x8);
var_ch = 0x0;
```

然后是一个条件跳转。

```asm
0x00407219      cmp     dword [var_ch], 8
0x0040721d      jae     0x407242
```

学习下`jae`指令。`jae`指令和`jnc`指令相同，`CF=0`则跳转。`jae` 可以看作 *Jump if above or equals*。上一句 `cmp` 计算 `var_ch - 0x8` ，对相关标志位赋值。`jae`指令根据`CF`标志位判断，由于`cmp`指令是减法，所以判断的是减法中有没有出现 *借位* 。

简单的描述就是，`cmp ax, bx`，如果`ax < bx` 则 `CF=1`，如果 `ax >= bx` 则 `CF=0`。

因为我们知道 `var_ch` 刚被初始化成了0，不成立，继续看不成立的分支。

```asm
0x00407223      mov     eax, dword [var_ch]
0x00407226      add     eax, 0x52  ; 82
0x00407229      mov     dl, al
; ---
0x0040722b      mov     eax, dword [var_8h]
0x0040722e      mov     ecx, dword [var_ch]
0x00407231      mov     byte [eax + ecx], dl
; ---
0x00407234      mov     eax, dword [var_ch]
0x00407237      add     eax, 1
0x0040723a      mov     dword [var_ch], eax
0x0040723d      jmp     0x407219
```

把`var_ch`移入寄存器`eax`后，加上`0x52`，又移动`al`到`dl`。后续`eax`被用作别的用途，这一番操作其实就是给`dl`赋值了一个`(int16_t)0x52+var_ch`。

随后把`var_8h`和`var_ch`相加后的地址赋值 `dl`，也就是`0x52`。

接着`var_ch`自增1，跳回 `jae`判断前的 `cmp`，形成循环，我们用伪代码表示。

```c
int var_4h, var_8h， var_ch; // ebp-4h, ebp-8h, ebp-ch
var_4h = 0x8;
var_8h = unknown_func(0x8);
var_ch = 0x0;
while(var_ch < 8) {
    *(var_8h + var_ch) = 0x52 + var_ch;
    var_ch++;
}
```

从结构上看，是一个典型的 for 循环。 `var_8h` 是一个未知函数返回的指针。我们稍微改下伪代码。

```c
int var_4h, var_8h; // ebp-4h, ebp-8h
var_4h = 0x8;
var_8h = unknown_func(0x8);

for (int var_ch=0; var_ch < 8; var_ch++) { // var_ch -> ebp-ch
    var_8h[var_ch] = 0x52 + var_ch;
}
```

接着继续看循环结束后的代码。

```asm
0x00407242      mov     eax, dword [arg_ch] ; ebp+ch 函数右往左数第二个入参
0x00407245      mov     ecx, dword [arg_8h] ; ebp+8h 函数右往左数第一个入参
0x00407248      mov     edx, dword [var_8h] ; ebp-8h
; ---
0x0040724b      mov     dword [esp], edx
0x0040724e      mov     dword [var_sp_4h], 8
0x00407256      mov     dword [var_sp_8h], ecx
0x0040725a      mov     dword [var_sp_ch], eax
0x0040725e      call    fcn.00407310
0x00407263      mov     dword [var_10h], 0
```

从之前分析主循环的代码，我们可以发现 `arg_8h` 其实是用户名字符串指针，`arg_ch`是用户名字符串长度。

接着这两个入参，和 `var_8h`，也就是之前得到指针，传入一个未知函数，随后再初始化了一个变量 `var_10h`。

伪代码如下。

```c
unknown_func(var_8h, 0x8, username, username_len); // 猜测的函数签名 func(void*, int, void*, int)
int var_10h = 0;
```

接着又是一个条件跳转。

```asm
0x0040726a      cmp     dword [var_10h], 8
0x0040726e      jae     0x407292
```

和先前的循环相同，不作重复分析，直接进入循环体。

```asm
0x00407274      mov     eax, dword [var_8h]
0x00407277      mov     ecx, dword [var_10h]
0x0040727a      movsx   edx, byte [eax + ecx]
0x0040727e      xor     edx, 0x25  ; 37
0x00407281      mov     byte [eax + ecx], dl
; ---
0x00407284      mov     eax, dword [var_10h]
0x00407287      add     eax, 1
0x0040728a      mov     dword [var_10h], eax
; ---
0x0040728d      jmp     0x40726a
```

前两条指令没什么可说的，`movsx`还是第一次见，学习下。

`movsx` 从来源取数，不足的部分用来源的符号位填充，这里取的是`var_8h[var_10h]`，一字节，到 `edx` 寄存器。`movsx`的好处是可以保留符号位，加载不同大小的数据时（比如来源是 `word`，目标是 `dword`），如果来源是负数，则填充符号位可以正确表示补码形式表示的负数。

从`var_8h[var_10h]`取数移入`edx` 后，之后是一句简单的 `xor`，逻辑异或运算。之后将`xor`运算结果取低位1字节（`dl`寄存器）移回`var_8h[var_10h]`。

之后自增，跳转循环，和之前的循环一样。将分析过的部分用伪代码表示如下。

```c
int var_4h, var_8h; // ebp-4h, ebp-8h
var_4h = 0x8;
var_8h = unknown_func(0x8);

for (int var_ch=0; var_ch < 8; var_ch++) { // var_ch -> ebp-ch
    var_8h[var_ch] = 0x52 + var_ch;
}

unknown_func(var_8h, 0x8, username, username_len); // 猜测的函数签名 func(void*, int, void*, int)
for(int var_10h=0; var_10h < 8; var_10h++) { // var_10h -> ebp-10h
    var_8h[var_10h] ^= 0x25;
}
```

继续看循环结束后的动作。

```asm
0x00407292      mov     dword [var_14h], 0x11 ; 17
0x00407299      mov     dword [esp], 0x11 ; [0x11:4]=-1 ; 17
0x004072a0      call    fcn.00401302
0x004072a5      mov     dword [var_18h], eax
0x004072a8      mov     dword [var_1ch], 0
```

调用一个函数，返回值赋值给`var_18h`，同时初始化`var_1ch`为 0。伪代码表示如下。

```c
int var_14h = 0x11;
var_18h = unknown_func(0x11);
int var_1ch = 0x0;
```

接下来又是一个循环。

```asm
0x004072af      cmp     dword [var_1ch], 8
0x004072b3      jae     0x4072f2
```

不重复分析，进入循环体。

```asm
0x004072b9      mov     eax, dword [var_8h]
0x004072bc      mov     ecx, dword [var_1ch]
0x004072bf      movsx   eax, byte [eax + ecx]
0x004072c3      mov     edx, dword [var_18h]
0x004072c6      mov     ecx, dword [var_1ch]
; ---
0x004072c9      shl     ecx, 1
0x004072cc      add     edx, ecx
; ---
0x004072ce      lea     ecx, str.02x ; 0x45de50，内容是 %02x
; ---
0x004072d4      mov     dword [esp], edx
0x004072d7      mov     dword [var_sp_4h], ecx
0x004072db      mov     dword [var_sp_8h], eax
0x004072df      call    fcn.00403dcd
; ---
0x004072e4      mov     eax, dword [var_1ch]
0x004072e7      add     eax, 1
0x004072ea      mov     dword [var_1ch], eax
0x004072ed      jmp     0x4072af
```

依然是从 `var_8h[var_1ch]` 取数，之后把 `var_18h` 和 `var_1ch` 也取数，分别放到 `eax`、`edx`、`ecx`。

接着是一个没见过的命令，`shl`，学习下。

`shl`是逻辑左移，和 c 中的 `<<` 运算符一样，两个操作数，命令格式`shl 寄存器,立即数`。

这里做的就是 `ecx`，也就是 `var_1ch` 的值左移1位，众所周知左移n位可以看作乘上2^n^ ，所以这句 `shl` 其实就是 `var_1ch*2`。左移后结果加到了`edx`，`edx`是`var_18h`。

之后是一个`lea`，加载地址，内容是常量字符串 `%02x`，看起来是一个 c 格式化字符串。

接着压栈传参，调用未知函数，结果忽略。伪代码表示如下。

```c
unknown_func(var_18h + var_1ch * 2, "%02x", var_8h[var_1ch]);
```

随后是变量自增，跳转回循环开头。

我们把分析出来的伪代码再合并下。

```c
int var_4h, var_8h; // ebp-4h, ebp-8h
var_4h = 0x8;
var_8h = unknown_func(0x8);

for (int var_ch=0; var_ch < 8; var_ch++) { // var_ch -> ebp-ch
    var_8h[var_ch] = 0x52 + var_ch;
}

unknown_func(var_8h, 0x8, username, username_len); // 猜测的函数签名 func(void*, int, void*, int)
for(int var_10h=0; var_10h < 8; var_10h++) { // var_10h -> ebp-10h
    var_8h[var_10h] ^= 0x25;
}

int var_14h = 0x11;
var_18h = unknown_func(0x11);
for(int var_1ch = 0x0; var_1ch < 8; var_1ch++) {
    unknown_func(var_18h + var_1ch * 2, "%02x", var_8h[var_1ch]);
}
```

最后是循环结束后的代码。

```asm
0x004072f2      mov     eax, dword [var_18h]
0x004072f5      mov     byte [eax + 0x10], 0
; ---
0x004072f9      mov     eax, dword [var_8h]
0x004072fc      mov     dword [esp], eax
0x004072ff      call    fcn.00402a36
; ---
0x00407304      mov     eax, dword [var_18h]
; ---
0x00407307      add     esp, 0x2c
0x0040730a      pop     ebp
0x0040730b      ret
```

首先是把`var_18h[0x10]` 的值设为0。

接着`var_8h`做参数调未知函数。

把`var_18h`移到`eax`，也就是`cdecl`约定下的返回值位置。

最后平栈，恢复`ebp`，返回，函数结束。我们把所有内容的伪代码合并起来。

```c
int var_4h = 0x8; // ebp-4h
void* var_8h = unknown_func(0x8); // ebp-8h

for (int var_ch=0; var_ch < 8; var_ch++) { // var_ch -> ebp-ch
    var_8h[var_ch] = 0x52 + var_ch;
}

unknown_func(var_8h, 0x8, username, username_len); // 猜测的函数签名 func(void*, int, void*, int)
for(int var_10h=0; var_10h < 8; var_10h++) { // var_10h -> ebp-10h
    var_8h[var_10h] ^= 0x25;
}

int var_14h = 0x11;
var_18h = unknown_func(0x11);
for(int var_1ch = 0x0; var_1ch < 8; var_1ch++) {
    unknown_func(var_18h + var_1ch * 2, "%02x", var_8h[var_1ch]);
}
var_18h[0x10] = 0;

unknown_func(var_8h);
return var_18h;
```

从这我们已经能看出具体算法了，未知函数可以猜测调试看看。

## 0x04 调试器 - easy

调试的目标是确认生成序列号的算法，把分析出的伪代码中还不清楚用途的未知函数，分析出作用。

### 4.1 x32dbg

打开调试器后，先找到关键跳，在工具栏点击字符串工具图标，在下方搜索栏输入`wrong pwd!` 

![image-20210915140718400](image/crackme-02/cm02-easy-15.png)

跳到引用位置。

![image-20210915111455604](image/crackme-02/cm02-easy-18.png)

![image-20210915111621678](image/crackme-02/cm02-easy-19.png)

之后可以按g，进入控制流视图，不过这个控制流视图有点不好看，我们也可以直接参考静态分析中的汇编，直接找到函数，并在入口下断点。

![image-20210915112358449](image/crackme-02/cm02-easy-20.png)

尝试随便输入一点内容，调试器命中。

![image-20210915112552389](image/crackme-02/cm02-easy-21.png)

接下来就可以用左上角的单步调试了。

![image-20210915140939909](image/crackme-02/cm02-easy-22.png)

不做更多介绍，汇编的分析已经进行过一次。这次我们找到对输入 "abc" 的正确序列号，完成一次解密。

只需要在断点处点击![image-20210915141120060](image/crackme-02/cm02-easy-23.png)按钮，然后观察`eax`寄存器。

![image-20210915141405302](image/crackme-02/cm02-easy-24.png)

抄出来（居然不能右键复制后面的字符串），内容是`4447467073727d7c`。

接着继续运行，再把抄出来的答案复制进去看看。

![image-20210915141838395](image/crackme-02/cm02-easy-25.png)

到这里，我们拿到了一个可以用的序列号。

## 0x05 注册机

### 5.1 Python 脚本注册机

先把前面的伪代码贴一下。

```c
int var_4h = 0x8; // ebp-4h
void* var_8h = unknown_func(0x8); // ebp-8h

for (int var_ch=0; var_ch < 8; var_ch++) { // var_ch -> ebp-ch
    var_8h[var_ch] = 0x52 + var_ch;
}

unknown_func(var_8h, 0x8, username, username_len); // 猜测的函数签名 func(void*, int, void*, int)
for(int var_10h=0; var_10h < 8; var_10h++) { // var_10h -> ebp-10h
    var_8h[var_10h] ^= 0x25;
}

int var_14h = 0x11;
var_18h = unknown_func(0x11);
for(int var_1ch = 0x0; var_1ch < 8; var_1ch++) {
    unknown_func(var_18h + var_1ch * 2, "%02x", var_8h[var_1ch]);
}
var_18h[0x10] = 0;

unknown_func(var_8h);
return var_18h;
```

里面的未知函数（失策，clang默认静态链接了libcmt，很多库函数在x32dbg里认不出来）猜一猜吧。

```python
username = input('username:').encode()
username_len = len(username)

var_4h = 8
var_8h = bytearray(8)

for i in range(8):
    var_8h[i] = 0x52 + i

# 这里的未知函数通过调试器可以看出，把入参复制到了 var_8h 里
var_8h[:username_len] = username

for i in range(8):
    var_8h[i] ^= 0x25

# for(int var_1ch = 0x0; var_1ch < 8; var_1ch++) {
#     unknown_func(var_18h + var_1ch * 2, "%02x", var_8h[var_1ch]);
# }
#
# 最后的那个循环中，函数判断为 sprintf 或其他啥，格式化明确是2位小写16进制数
# 前面的计算看作是算偏移，一个 var_8h 的字节对应 2 字节16进制表示，所以 var_18h 加上 NUL 一共是 0x11 也就是 17 个字节
# 循环的作用是把 var_8h 这个字节数组转换成16进制表示的字符串。
#
# 在 python 里用 hex() 就行了。
print(var_8h.hex())
```

运行脚本，输入`abc`，输出`4447467073727d7c`，确认注册机可以生成序列号。

## 0x06 修改 exe

### 6.1 x32dbg 修改关键跳

用调试器打开后找到决定serial是否正确的关键跳转，右键二进制选择用NOP填充，确认即可。

![image-20210915150907420](image/crackme-02/cm02-easy-26.png)

修改后效果如图。

![image-20210915150953046](image/crackme-02/cm02-easy-27.png)

接着把修改后的exe保存下来，在文件菜单里选择补丁。

![image-20210915151220354](image/crackme-02/cm02-easy-28.png)

全选，点修补文件，选择路径保存。

![image-20210915151322628](image/crackme-02/cm02-easy-29.png)

我保存在`cm02-easy-patched.exe`，接着我们试试运行。

![image-20210915151903611](image/crackme-02/cm02-easy-30.png)

遗憾的是被x32dbg补丁功能导出的文件需要管理员权限运行，为了能截到图，图中用了名为`sudo`的工具命令，可以用`scoop install sudo`来安装`sudo`，点击去[scoop首页](https://scoop.sh)。

### 6.2 反编译器修改关键跳

以Cutter为例，找到`jne`指令后，右键修改为`nop`即可。记得先备份。

![image-20210915152428449](image/crackme-02/cm02-easy-31.png)

![image-20210915152609774](image/crackme-02/cm02-easy-32.png)

修改后也能实现和x32导出一样的效果，而且不用管理员权限。

## 结论

总得有个结论。

这次逆向应该能帮助学到下面的东西：

- 栈帧结构和函数调用
- `cmp`指令
- `jne`、`jbe`、`jnz`、`jae`指令
- `movsx`指令
- `shl`指令

库函数因为静态链接的缘故已经变成了文中的未知函数，造成了分析上的障碍。老实说如果不是自己写的源码，能不能这么顺利逆向出注册机还真不好说。

开启优化的 *normal* 和 *hard* 难度就不进一步分析了，有兴趣可以看看。
