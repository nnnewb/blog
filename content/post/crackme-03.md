---
title: 自娱自乐 crackme-03
slug: crackme-03
date: 2021-09-24 16:58:00
categories:
- 逆向
tags:
- 汇编
- 逆向
---



## 前言

总得有个前言。

一直玩命令行 crackme 看着就没啥意思，来点带界面的。依然是学习用，目标是把汇编和底层和内存这套东西读熟。这次是用 wxwidgets 做的简单 crackme，为了在 CrackME-02 基础上再增加点难度但又不至于太难，这次是 OTP 生成序列号，要求解出生成 OTP 的 SECRET。

## 源码

越来越长了，贴上来没法看。现在托管到GitHub，包括前面的两个cm。

前两个cm托管的代码编译参数有一点修改，可能造成结果和文章不一致，但大体是一样的，别在意。

源码托管地址：[github.com/nnnewb/crackmes](https://github.com/nnnewb/crackmes/)

挑战一下C++代码开启优化的Hard模式。

## 观察

![image-20210923104439284](image/crackme-03/01.png)

一个输入框，点击try it尝试。失败时提示Wrong，没有别的信息。

## 静态分析

老规矩先静态分析一波，粗略扫一眼，捋一捋逻辑。用你喜欢的反汇编工具打开，我用Cutter先试试。

因为是GUI程序，直接跳`main`肯定是不行的。Win32 GUI程序的入口点（程序员视角）在`WinMain`这个特殊函数，不过真拿Win32API手撸界面我是真没见过了，Win32 GUI程序设计也是玩的事件响应，找到主函数的意义不大。

所以找关键跳这一步只能是从数据段找字符串查引用，或者调试器下合适的访问断点了。

这里直接从数据段找到了字符串，定位到弹出错误对话框的逻辑。

![image-20210923105415082](image/crackme-03/02.png)

这里有个姿势点是`__thiscall`，这是个微软自定义的调用约定，点这里看[微软的文档](https://docs.microsoft.com/zh-cn/cpp/cpp/thiscall?view=msvc-160)。

### __thiscall

`__thiscall`的特点是被调用方清栈，`this`指针通过`ecx`寄存器传递，其他参数右至左压栈。对于可变长度参数（VAARG）的成员函数会特殊处理，采用`cdecl`调用约定，`this`指针最后压栈。

这里简单读一下定位到的几句代码，分析下意图。

```

0x004064dc      68 34 e8 40 00              push    str.Try_again ; 0x40e834
0x004064e1      8d 4d d0                    lea     ecx, [ebp - 0x30]
0x004064e4      ff 15 e0 33 41 00           call    dword [public: void __thiscall wxString::constructor(char const *)] ; 0x4133e0
0x004064ea      68 44 e8 40 00              push    str.Wrong ; 0x40e844
0x004064ef      8d 4d b0                    lea     ecx, [ebp - 0x50]
0x004064f2      c6 45 fc 07                 mov     byte [ebp - 4], 7
0x004064f6      ff 15 e0 33 41 00           call    dword [public: void __thiscall wxString::constructor(char const *)] ; 0x4133e0
0x004064fc      6a ff                       push    0xffffffffffffffff
0x004064fe      6a ff                       push    0xffffffffffffffff
0x00406500      6a 00                       push    0
0x00406502      6a 05                       push    5 ; 5
0x00406504      8d 45 d0                    lea     eax, [ebp - 0x30]
0x00406507      c6 45 fc 08                 mov     byte [ebp - 4], 8
0x0040650b      50                          push    eax
0x0040650c      8d 45 b0                    lea     eax, [ebp - 0x50]
0x0040650f      50                          push    eax
0x00406510      ff 15 d4 3c 41 00           call    dword [int __cdecl wxMessageBox(class wxString const &, class wxString const &, long int, class wxWindow *, int, int)] ; 0x413cd4
```

反编译器对调用的第三方库的函数分析极大降低了肉眼判读的难度。可以看到前三步`push`、`lea ecx,...`、`call` 是典型的 `__thiscall` 调用，调用对象是`wxString`的构造器，所以可以知道`ecx`地址保存的是一个`wxString`对象的指针。

```
0x004064ea      68 44 e8 40 00              push    str.Wrong ; 0x40e844
0x004064ef      8d 4d b0                    lea     ecx, [ebp - 0x50]
0x004064f2      c6 45 fc 07                 mov     byte [ebp - 4], 7
0x004064f6      ff 15 e0 33 41 00           call    dword [public: void __thiscall wxString::constructor(char const *)] ; 0x4133e0
```

这是另一个`wxString`的构造。

```
0x004064fc      6a ff                       push    0xffffffffffffffff
0x004064fe      6a ff                       push    0xffffffffffffffff
0x00406500      6a 00                       push    0
0x00406502      6a 05                       push    5 ; 5
0x00406504      8d 45 d0                    lea     eax, [ebp - 0x30]
0x00406507      c6 45 fc 08                 mov     byte [ebp - 4], 8
0x0040650b      50                          push    eax
0x0040650c      8d 45 b0                    lea     eax, [ebp - 0x50]
0x0040650f      50                          push    eax
0x00406510      ff 15 d4 3c 41 00           call    dword [int __cdecl wxMessageBox(class wxString const &, class wxString const &, long int, class wxWindow *, int, int)] ; 0x413cd4
```

连续推入多个参数后，调用了`wxMessageBox`函数。我们知道`[ebp-0x30]`是`Try again`，`[ebp-0x50]` 是 `Wrong!`，这个调用用伪代码表示就是 `wxMessageBox("Wrong!", "Try again!", 5, 0, -1, -1)`。注意忽略中间的`mov     byte [ebp - 4], 8`，`ebp-4`这个偏移显然不大可能是参数。

### 关键跳

回到这段代码的开头，顺着界面上的绿色箭头找到关键跳。

![image-20210923111554787](image/crackme-03/03.png)

一个`je`跳转，`je`指令检查`ZF`，向上一行就是`test`，`test bl,bl`自己对自己逻辑与，其实就是求`bl`是不是0。

bl又来自前面的`mov bl,al`，`al`寄存器是`eax`寄存器的低8位，再者大家也知道`eax`寄存器是函数返回值保存的寄存器，而离这个`mov`指令最近的`call`就是截图上方的`IsSameAs`函数了。

到了这一步，改指令跳过验证已经接近成功了，但这要是做 keygen 的话还不行。

继续往回翻，寻找密码生成的代码。

### 寻找密码生成算法

先一路回到关键跳所处的代码块顶部，挨个往下看有哪些函数调用。

![image-20210923113330184](image/crackme-03/04.png)

还是那句话，感谢分析出了库函数，不然一堆未知函数看得满头雾水。

1. 调用是 `wxString.AsWChar(void)`，顾名思义是取宽字符，返回指针。

2. 调用是`wxString.DoFormatWchar(wchar_t*)`，查询文档可知是个类似`sprintf`的字符串格式化函数。

3. 调用是析构函数，怀疑上面的两个调用其实是内联了什么wxwidgets库的代码。因为直觉告诉我如果还没离开作用域，编译器应该不会这么着急插入析构函数调用，这听起来就没什么好处，还违背码农直觉。

4. 函数就比较迷惑了，一路看上去的话会发现这个偏移值经过了多次计算，目前看不出用意，但还挺可疑的。

5. 函数顾名思义，比较字符串相等。

6. 又是析构函数。

重点看字符串比较函数的参数：

```asm
0x0040646c      6a 01                       push    1 ; 1
0x0040646e      8d 4d 90                    lea     ecx, [ebp - 0x70]
0x00406471      c6 45 fc 04                 mov     byte [ebp - 4], 4
0x00406475      51                          push    ecx
0x00406476      8b c8                       mov     ecx, eax
0x00406478      ff 15 d4 33 41 00           call    dword [public: bool __thiscall wxString::IsSameAs(class wxString const &, bool)const] ; 0x4133d4
```

把`eax`当成了`this`，暂且不看栈上的`ebp-0x70`，看到`eax`立刻就发现是来自第四个比较迷惑的函数调用，实锤这函数就是生成密码的函数。

## 动态调试

水平有限，静态分析很快遇到了瓶颈，找不出这个偏移值算出来的函数到底在哪儿。

于是启动调试器，先跟到我们定位到的这个特殊函数。

![image-20210923140108796](image/crackme-03/05.png)

惊喜地发现胡乱分析出现了错误，`eax+0x40`其实是获取输入框值的函数。。所以另一个参数，`ebp-0x70`才是密码。

往回看`ebp-0x70`在`DoFormatWchar`被当参数传递了进去，要注意的是`DoFormatWchar`是一个有变长参数的函数，这意味着你没法得知传了几个参数（前面push的内容不一定是当参数传了），分析更困难。

看一下`DoFormatWchar`这段汇编。

```asm
0x0040642c      8d 8d 70 ff ff ff           lea     ecx, [ebp - 0x90]
0x00406432      ff 15 e8 33 41 00           call    dword [private: wchar_t const * __thiscall wxFormatString::AsWChar(void)] ; 0x4133e8
0x00406438      56                          push    esi
0x00406439      50                          push    eax
0x0040643a      8d 45 90                    lea     eax, [ebp - 0x70]
0x0040643d      50                          push    eax
0x0040643e      ff 15 d0 33 41 00           call    dword [private: static class wxString __cdecl wxString::DoFormatWchar(wchar_t const *)] ; 0x4133d0
```

一共推了三个东西入栈，esi、eax（上一个调用的返回值）、还有`[ebp-0x70]`。

继续调试器跟一遍看看。

![image-20210923142010900](image/crackme-03/06.png)

`esi`的值比较怪，先忽略。

`eax`比较清楚，宽字符串`%06d`，按压栈顺序，`esi`的值是紧跟在格式化字符串后面的参数。

![image-20210923142347785](image/crackme-03/07.png)

最后压栈的eax，也就是ebp-0x70的地址，用伪代码表示就是：`DoFormatWchar(&var_70, L"%06d", 0x000F18D8)`。PS：有点怪，函数签名最左侧是format也就是格式化字符串，最后压栈这个ebp-0x70就有点莫名其妙。

![image-20210923143534148](image/crackme-03/08.png)

不过用调试器单步步过后就知道用途了，和猜测的一样，存放的是格式化的结果，也就是正确的密码。

既然如此，往回找esi是哪儿赋值的，因为inline了一大堆东西，Cutter连函数都认不出来了，控制流视图也挂了。。一直往上翻，找到`0xcc`或者`push ebp; mov ebp, esp`为止。

![image-20210923145922049](image/crackme-03/09.png)

右键选择在此处定义函数，随便给个名字，然后等Cutter分析好函数体。

![image-20210923150100196](image/crackme-03/10.png)

这样一来至少图形视图就能看了。粗略扫一眼，在底下找到`IsSameAs`这个调用，再往回翻哪儿动了`esi`这个寄存器，很快找到这两段。

![image-20210923150438821](image/crackme-03/11.png)

有点杂，先看看。还是粗略按意图把指令分下段。`esi`来源涉及`eax`和`ecx`，一路跟着赋值路径往回翻到第一个块，找到`ecx`的赋值。

```asm
0x004062f1      e8 68 b3 ff ff              call    fcn.0040165e
0x004062f6      8b 08                       mov     ecx, dword [eax]
```

一个未知函数，ctrl+左键点击跟进去后发现疑似是 libcrypto 内联的函数，调用了 HMAC-SHA1 算法。

![image-20210924092624224](image/crackme-03/12.png)

先做个标记，猜测假设这个函数正确返回（下面的je跳转走到最后一个块），那返回结果应该是HMAC-SHA1的结果。这里通过调试器单步验证。

因为 ASLR 的缘故，可执行文件 .text 段映射的地址不是 0x00401000，调试器没法直接转到静态分析工具中的地址，ASLR 确实折磨人...

anyway...

我投翔，特立独行是没好结果的，跑去下载了一个 IDA Free ，打开x32dbg确认 .text 段映射的基址后再到 IDA 的菜单 `Edit` -> `Segments` -> `rebase program ...` 重新设定镜像基址，这样在反汇编界面看到的地址就能和调试器对上了。缺陷是每次打开调试器都要对一次镜像基址，比较麻烦。

![image-20210924154631893](image/crackme-03/image-20210924154631893.png)

对好镜像基址后，把之前想调试的函数调用地址找到（0x003B62F1），下个断点，看调用后的`eax`值，发现并不像纯c编译出来的结果，`eax`并没有什么卵用。

稍微往上瞟了一眼，很容易看到一个`mov ecx,esi`，但没什么卵用。

碰壁几次后决定跟进这个函数看看。无果。恼，作弊之（读过RFC可能注意到几个特殊常量，比如取哈希结果下标19，与0xf，作为偏移值向后再取4字节，作为bin code。跳过这个函数调用，直接看接下来的内容的话，会发现哈希值其实就存在`ecx`保存的地址上了。）

![image-20210924162043275](image/crackme-03/image-20210924162043275.png)

只是这里的HMAC_SHA1值因为不是我们熟悉的ASCII表示，所以一眼有点难看出来。

那么直接跳过上面不清不楚的地方，直接看取哈希后的做法。

```asm
.text:003B6307 movzx   eax, byte ptr [ecx+13h]
.text:003B630B and     eax, 0Fh ; 取 hash[19] & 0xf 作为初始偏移
.text:003B630E add     ecx, eax
.text:003B6310 movzx   esi, byte ptr [ecx] ; 取偏移处第一个字节，无符号
.text:003B6313 movzx   eax, byte ptr [ecx+1] ; 取偏移处第二个字节，无符号
.text:003B6317 and     esi, 7Fh ; 偏移处第一个字节 & 0x7f ，确保符号位归零
.text:003B631A shl     esi, 8 ; 第一个字节左移8位后 | 第二个字节，就是把四个字节按顺序填进esi
.text:003B631D or      esi, eax
.text:003B631F movzx   eax, byte ptr [ecx+2]
.text:003B6323 shl     esi, 8
.text:003B6326 or      esi, eax
.text:003B6328 movzx   eax, byte ptr [ecx+3]
.text:003B632C shl     esi, 8
```

取得的就是4字节正整数了，按RFC的例子，接下来应该取模得到最大6位整数。看下一块汇编。

```asm
.text:003B6331 mov     ecx, [ebp+Block]
.text:003B6334 mov     eax, 431BDE83h ; magic ?
.text:003B6339 imul    esi
.text:003B633B sar     edx, 12h
.text:003B633E mov     eax, edx
.text:003B6340 shr     eax, 1Fh
.text:003B6343 add     eax, edx
.text:003B6345 imul    eax, 0F4240h
.text:003B634B sub     esi, eax
.text:003B634D test    ecx, ecx
.text:003B634F jz      short loc_3B638F
```

`431BDE83h` 这个魔术常量吓到我了。搜了一下找到篇[看雪的帖子](https://bbs.pediy.com/thread-100189.htm)，看起来是编译器把一句`%1000000`取模给编译成了上面这一串满是魔数的汇编。尝试跟到 `sub esi,eax` 后，`esi` 寄存器的结果的确变成了6位以内的整数。

这玩意儿有什么特征吗？总不至于多做几次取模，生成的汇编就完全没法看了吧。。。

## keygen？

实力有限，尽管亲手写下的C++代码真的很简单，但编译后的结果成了无法承受之重...

上面分析的内容，其实仔细对着RFC推敲（首先，你得知道是照着RFC写的，不然就多读几遍汇编...），才能很勉强得到个粗糙的算法，至于能不能写出 keygen，我没啥信心。

## 结论

很难。

如果说前面的 C 代码是小游戏的话，那 cm03 就是地球online。开启优化的C++无间地狱。

完全溃败。
