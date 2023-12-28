---
title: nasm汇编手写个PE可执行文件
slug: hand-write-PE-file-with-nasm-assembly
date: 2021-10-13 11:05:00
categories:
- 汇编
tags:
- 汇编
- 逆向
- windows
---



## 前言

主要是虽然有个汇编器 nasm 但是不知道怎么用，啥汇编都是调试器里纸上谈兵。最近碰到个问题，MinGW 可以用参数 `-Wl,section-start=` 来修改 section 地址，但 *msvc* 没有对应物，就蛋疼。手动改 PE 来添加 section 好像可行，但不知道该怎么做，lief 也不熟悉。

正好瞎谷歌的时候发现 nasm 可以直接编译出 PE 文件，这就听起来很有意思了。汇编嘛，听着就很底层，很自由，改个 Section 地址不是手到擒来。于是就学学看。

参考文章附于文末。

## 0x01 nasm 基本用法

### 1.1 label

汇编当然有经典的 *label* 和 *instruction* 了，*instruction* 的参数就叫 *operand* 。

nasm 的 label 语法很简单，任何不是宏和 *instruction* 或者伪指令的东西，出现在行首，都会被认作 label。

```asm
lbl1: ; 这是label
	sub esp, 4h
	jmp lbl
lbl2   ; 这也是 label
	sub esp, 4h
lbl3 db 1 ; 这还是 label
.label4 ; 这是本地 label，可以用 .label4 或者全称 lbl3.label4 访问
.@label5 ; 这是特殊 label ，只能在宏里使用，避免干扰本地label
```

label 可以被视作一个数字参与运算，比如说 `lbl3-lbl2` 这样算出偏移。或者还可以参数伪指令计算。总之用处很多。

### 1.2 伪指令

伪指令是一些并不是真正的 x86 机器指令，但还是被用在了 instruction 域中的指  令，因为使用它们可以带来很大的方便。当前的伪指令有`DB`,`DW`,`DD`,`DQ`和  `DT`，它们对应的未初始化指令是 `RESB`, `RESW`,` RESD`,` RESQ` 和 `REST`，`INCBIN`  命令，`EQU` 命令和 `TIEMS` 前缀。

不复制粘贴了，看文档好吧。

### 1.2 有效地址

有效地址是指令的操作数，是对内存的引用。nasm中有效地址的语法非常简单：由一个可计算表达式组成，放在中括号内。

```asm
wordvar:
	dw 123
	mov ax, [wordvar] ; [wordvar] 就是取 dw 123 的首地址
	mov ax, [wordvar+1] ; wordvar+1 label 参与算术运算，取 dw 123 地址 + 1字节
	mov ax, [es:wordvar+bx] ; 加上段选择子，寄存器参与运算
```

与上例不一致的表达式都不是 nasm 的有效地址，比如 `es:wordvar[bx]` 。

还可以用 `BYTE` `WORD` `DWORD` `NOSPLIT` 等关键字强迫 nasm 产生特定形式的有效地址。比如 `[dword eax+3]` 。

详细还是看文档。

### 1.3 常数

支持的常数类型包括：

- 数值

  - `100` 10进制
  - `100h` 16进制，`h`结尾
  - `0x100` 16进制，`0x`开头
  - `$0100` 16进制，`$0`开头
  - `777q` 8进制，`q`结尾
  - `10010011b` 2进制，`b`结尾

- 字符

  - `abcd` 字符型常数，小端序

- 字符串

  - 一般只有伪指令接受，形式如 `db 'abcd'` 、`db 'a','b','c','d'` 。

- 浮点数

  - 反正用不到我也懒得看。

### 1.4 表达式

和C的差不多，除了+-*/%和位运算，多了个 `//` 表示带符号除法，`%%` 表示带符号取模。

###  1.5 预处理器

预处理器指令以 `%` 开头。举几个例子

```asm
%define FOO BAR
%define FN(x) (x+1)
%include "xxx.asm"
%undef FOO
```

其他懒得写了，先知道这几个和C类似的宏就行，更多看文档。

### 1.6 汇编器指令

提几个会用到的。

`BITS`，指定目标处理器模式，比如 `BITS 32` 就是32位模式。现在找16位的环境怕是也难。

`SECTION`，改变正在编写的代码要汇编进的段。要是打算汇编成 `obj` 让链接器去链接出新文件会有点用。但是输出格式是 `bin` 的时候就没有卵用了。

`EXTERN`，导入外部符号，还是汇编成 `obj` 让链接器用的时候会有点用，链接器会搞定链接，输出格式是 `bin` 的时候就没卵用。

`GLOBAL`，导出符号，和`EXTERN`的应用场景差不多。熟悉C的码农应该能理解。

### 1.7 输出格式

几个值得关注的输出格式。

`-f win32` 就是输出成 win32 对象文件 `.obj`，之后可以用 `gcc` 或者 `link.exe` 之类的东西链接。

`-f bin` 输出成二进制文件，你写了啥就输出啥，nasm 就是个翻译官。`.COM`和`.SYS`都是纯二进制格式的，你要是写这些可能有用。还有操作系统引导程序之类的纯二进制程序，不需要别的什么文件格式的情况。

`-f elf` 你要是写 linux 下的程序就有用。

### 1.8 总结

基本就是这样，更多东西就现查现用好吧。善用谷歌。

## 0x02 简单汇编程序

先写一个简单的汇编程序，不直接产生可执行文件，而是需要链接器进一步链接。例子需要安装 MinGW。

```asm
section .data
    global HelloWorld

HelloWorld:
    db 'hello world',0 ; 定义一个字符串常量，用于输出

section .text
    global _main ; _main 就是 C 的 main, 用于让链接器识别出入口点，生成命令行程序
    extern _printf ; _printf 就是 C 的 printf, 用于输出 hello world

_main:
    push ebp ; 其实我们自己写就不用啰嗦 push ebp/mov ebp,esp 了, 心里有底就行
    mov ebp, esp
    push HelloWorld ; 压入字符串常量的地址做参数
    call _printf    ; 调用 printf 输出
    add esp, 4      ; 根据 cdecl 约定，完成平栈
    pop ebp         ; 要返回一个值的话可以再加一行 mov eax, 0 等同于 return 0
    retn            ; 完事
```

编译命令，要安装 MinGW 才有 gcc 可以用。或者其他链接器也可以，GoLink 好像就行，但是我没用过。

```shell
nasm main.asm -f win32 -o main.o
gcc main.o -o main.exe
```

生成的代码放进调试器看看。

![image-20211013092916141](image/nasm手写个PE可执行文件/image-20211013092916141.png)

可以看到我们的汇编代码忠实地出现在调试器里。

这就是 nasm 的简单用法了，想要拿汇编写一点简单的验证代码是没问题的，也可以手写汇编函数，再链接到 C/C++ 代码里。当然，写 C/C++ 的大佬大概也知道 Visual C++ 支持内嵌汇编，`__asm {}` 就行，这也算一种选项。

## 0x03 生成二进制代码

使用 `nasm -f bin` 可以直接从汇编代码生成二进制文件，也就是没有链接这一步。

当然，没有链接这一步（或者说链接相关信息不由 nasm 管理），`global` 和 `extern` 都没有意义，在 `-f bin` 时汇编器会直接提示错误，不能使用。但相对的，因为 nasm 没自动生成更多信息，我们也对汇编结果有了更强的控制力，也要负担更多责任。

### 3.1 生成 DOS 文件头

PE 文件格式不再赘述，参考微软的 [PE Format](https://docs.microsoft.com/en-us/windows/win32/debug/pe-format) 文档，或者维基百科的 PE 格式图即可。

先从生成 PE 文件的文件头开始，填充可执行文件的必要信息。

```asm
BITS 32

; 由编译器生成的 DOS 文件头其实包含了一段输出 This program cannot be run in DOS mode 的代码
; 我们不需要，这里直接忽略。
dos_header:
    .magic    dw    "MZ" ; dw 伪指令会放置一个双字节 word, 也就是操作数 MZ
    .cblp     dw     90h ; 90h 就是 0x90
    .cp       dw     3
    .crlc     dw     0
    .cparhdr  dw     4
    .minalloc dw     0
    .maxalloc dw     -1
    .ss       dw     0
    .sp       dw     0B8h
    .csum     dw     0
    .ip       dw     0
    .cs       dw     0
    .lfarlc   dw     40h
    .ovno     dw     0
    .res      times  4 dw 0 ; 伪指令 times 重复 n 次，放置 4 个双字节 word ，值为 0
    .oemid    dw     0
    .oeminfo  dw     0
    .res2     times  10 dw 0
    .lfanew   dd     .next    ; 紧随其后的就是 NT 文件头了，所以 lfanew 直接指向自己末尾后
    .next:
```

关于链接器自动生成的文件头，可以参考这篇文章 [a closer look at portable executable MS-DOS stub](http://blog.marcinchwedczuk.pl/a-closer-look-at-portable-executable-msdos-stub) 。

反正咱无脑复制了。

### 3.2  生成 PE 文件头

生成 PE 文件头之前我们要预先考虑几个要素。

- 文件如何对齐？

  对齐到 0x400，大部分内容都可以在一个 0x400 里填写完，计算量比较少。

- Section 如何对齐？

  对齐到 0x1000，同样是简化计算。

- 需要几个 Section？

  一个 `.text` 就足够了。

其余文件头内容，出于简单考虑，包括重定位和 IAT 在内的大部分东西都留空，仅仅写一个什么效果都没有的可执行文件。

```asm
nt_header:
pe_signature:
    .sig                    dd      "PE" ; 魔术标识, dd 伪指令填充一个 DWORD, 结果是 PE\0\0

file_header:
    .machine                dw      0x014c ; 支持 Intel I386
    .numberofsections       dw      0x01   ; 本文件包含一个 Section
    .timedatestamp          dd      0
    .pointertosymboltable   dd      0
    .numberofsymbols        dd      0
    .optheadersize          dw      $OPT_HEADER_SIZE ; opt_header_size 会在稍后的 optional_header 末尾计算得到
    .characteristics        dw      0x102 			; 声明本文件是一个32位Windows可执行程序

optional_header:
    .magic                      dw 0x10b
    .linker_version             db 8,0
    .sizeof_code                dd 1000h ; 共包含 0x1000 字节的代码段
    .sizeof_initialized_data    dd 0
    .sizeof_uninitialized_data  dd 0
    .addressof_entrypoint       dd 1000h ; 入口点 RVA
    .baseof_code                dd 1000h ; 代码段 RVA
    .baseof_data                dd 0h    ; 数据段 RVA, 没有数据段就留空了
    .image_base                 dd 4000000h ; 镜像基址 0x04000000, 后面是 6 个 0
    .section_alignment          dd 1000h ; section 对齐到 1000h
    .file_alignment             dd 400h  ; 文件对齐到 400h
    .os_version                 dw 4,0
    .img_version                dw 0,0
    .subsystem_version          dw 4,0
    .win32_ver_value            dd 0
    .sizeof_img                 dd 2000h ; 请求的镜像总大小，文件头到代码段起点共 1000h, 代码段 1000h, 共计 2000h
    .sizeof_headers             dd 400h  ; 文件头大小对齐到了 400h, 我们知道文件头肯定不足 400h, 所以 sizeof_headers 直接填 400h 就行
    .checksum                   dd 0
    .subsystem                  dw 2
    .dll_characteristics        dw 0x400 ; 不支持 SEH, 不开启 ASLR
    .sizeof_stack_reserved      dd 0x100000
    .sizeof_stack_commit        dd 0x1000
    .sizeof_heap_reserved       dd 0x100000
    .sizeof_heap_commit         dd 0x1000
    .loeader_flags              dd 0
    .numberof_rva_and_sizes     dd 10h   ; 后续有 16 个 Data Directories

data_directories:
    times 10h dd 0, 0 ; 所有的 data directories 填充 0

; 通过伪指令 equ ，给 $OPT_HEADER_SIZE 赋值为 (当前地址 - optional_header标签)
; 也就是整个 optional_header 的大小
$OPT_HEADER_SIZE equ $ - optional_header

section_table:
    .text:
        db ".text", 0, 0, 0                     ; section name
                                                ; 注意对齐到了 8 字节，不足部分 0 填充, 不能超出
        dd 1000h                                ; virtual size
                                                ; Section 使用的内存大小
        dd 1000h                                ; virtual address
                                                ; Section 的起始点 RVA
        dd 400h         					  ; sizeof raw data
                                                ; 我们知道对齐到了 400h 且代码肯定比这少, 所以 raw data 必然有 400h 大小
        dd code                                 ; pointer to raw data
                                                ; 用 label 告诉汇编器 raw data 的偏移
        dd 0                                    ; pointer to relocations
        dd 0                                    ; pointer to linenum
        dw 0                                    ; number of relocations
        dw 0                                    ; number of linenum
        dd 0x60000020                           ; characteristics
                                                ; 含义是：代码段 - 可读

align 400h, db 0
; align 伪指令，不足的部分填充0, 对齐到 400h
; 相对文件头到这里, 肯定是不足 400h 的, align 伪指令会填充到满 400h 为止。
; 这样一来, 整个文件头大小, 正好就是 400h
```

### 3.2 编写汇编代码

文件头定义完成后，就可以开始写汇编代码了。正常这时候还要处理导入表，但我们跳过了。

```asm
code:
.start:
	xor eax, eax
	retn

align 400h, db 0 ; 同样，再次对齐到 400h ，把代码段的剩余部分填充成 0
```

到这里，整个 PE 文件的内容就填写完毕了。

文件头的绝大多数字段并不是我们关注的对象，计算偏移和对齐是最蛋疼的。

### 3.3 关于对齐的坑

> There are additional restrictions on image files if the SectionAlignment value in the optional header is less than the page size of the architecture. For such files, the location of section data in the file must match its location in memory when the image is loaded, so that the physical offset for section data is the same as the RVA.

微软文档里指出，在 Section 对齐的大小小于体系结构指定的页大小（4K）的时候，会有个额外限制，要求 Section 数据在文件中的偏移 **必须** 对应在内存中的 RVA 。也就是说，如果 Section 对齐为 1 字节，`VirtualAddress` 指定为 1000h，那 Section 数据必须存放在文件的 1000h 偏移处，否则生成的可执行文件会出现“不是有效的Win32应用程序”错误。

### 3.4 其他坑

建议不要参考单独的某几篇文章，多找些相关的文章博客和文档，互相对照着看。PE格式错误不会有具体的提示，我也没找到什么好用的工具去检查到底哪儿有错，只能建议多用用 CFF Explorer 和 lief、pefile 这些能检查文件格式的库了，要是这些都不行那就看看16进制编辑器什么的吧，比如 HexWorkshop。IDA 在这儿没啥用。

另外我还发现1字节对齐的时候，x32dbg 调试会看不到汇编代码，在内存布局里进入自己的PE文件后只能看到PE头，但没有反汇编。不过调试器还是可以正常单步调试和查看寄存器。

### 3.5 编译

上面的汇编代码用 nasm 即可编译，不需要其他编译或链接工具了。

```shell
nasm pe.asm -f bin -o pe.exe
```

![image-20211013104216658](image/nasm手写个PE可执行文件/image-20211013104216658.png)

也可以放进调试器看看。

![image-20211013104451137](image/nasm手写个PE可执行文件/image-20211013104451137.png)

可以看到，代码段正确出现在 4001000h 这个地址上（基址+1000h），内容也符合我们写的汇编代码。

![image-20211013104646905](image/nasm手写个PE可执行文件/image-20211013104646905.png)

在内存布局窗口也能看到。

## 总结

这是个对 PE 文件格式有所了解后的一个简单应用，原先是只会拿其他编程语言去读 PE 文件头的内容，现在学会了用汇编器去写一个简单的 PE 文件。之所以是汇编器去写，而不是拿 C/C++/Python 去写，还是因为我菜而且懒。好了跳过关于我菜的话题吧。

参考文档（不分先后）：

- http://blog.marcinchwedczuk.pl/a-closer-look-at-portable-executable-msdos-stub
- https://docs.microsoft.com/en-us/windows/win32/debug/pe-format
- https://reverseengineering.stackexchange.com/questions/11758/how-do-you-calculate-address-start-size-of-pe-section-like-rdata-data
- http://www.phreedom.org/research/tinype/
- https://stackoverflow.com/questions/17456372/create-and-use-sections-for-pe-file-in-assembly-nasm
- https://bitcodersblog.wordpress.com/2017/05/10/win32-in-nasm-part-1/

大部分代码其实是来自 tinype，被我调来调去改了很多。自己动手折腾一遍远比走马观花看一遍收获更多，有些实践问题不跟着抄一次改一改是不会发现的。有言道“实践出真知”，虽然说现在有些沙雕把生活经验当成真理导致一帮人捧书本一帮人捧经验，搞得啥事情都非黑即白...把伟人的话当成互相攻讦的武器。

淦，好好的学习，结果总结的时候越想越气。

果然，“人类的悲欢并不相通，我只觉得他们吵闹。”
