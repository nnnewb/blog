---
title: 加壳原理06：反调试技术入门
slug: learning-packer-06
date: 2021-10-27 19:50:00
image: cover.jpg
categories:
- 逆向
tags:
- 逆向
- c++
- windows
- 汇编
- security
- binary-analysis
---

## 前言

反调试技术，往大了说是用尽一切手段防止运行时对程序的非法篡改和窥视，往小了说就是防调试器。反正反调试这件事和各种技术都能搭点边，什么HOOK啦DLL注入啦。真要给涉及到的各方面都说得头头是道，那我这个菜鸡就不叫菜鸡了。

反正涉及的各种技术细节吧，将来都会慢慢学到的。也不急于一时。本篇关注的重点还是在导，引入，了解个大概。看看有什么反调试思路，对付这些反调试技术又有什么 bypass 的手段。

说这么多，其实还是找了篇写得不错的外文文章，抄了然后调试了下案例。

## 0x01 反调试思路

首先概述一下本篇主要的反调试思路。

### 1.1 系统API或数据结构

操作系统提供了一些调试标志位，调试器启动的进程会有标识。调试器也可能会为了提供更好的调试体验，修改一些参数，让我们有迹可循。

1. `PEB->BeingDebugged`和`IsDebuggerPresent`
2. `PEB->NtGlobalFlag`
3. `PEB->HEAP->Flags`和`PEB->HEAP->ForceFlags`
4. `CheckRemoteDebuggerPresent`
5. `NtQueryInformationProcess`
   1. `ProcessDebugPort`
   2. `ProcessDebugObjectHandle`
   3. `ProcessDebugFlags`
   4. `ProcessBasicInformation`
6. `NtSetInformationThread`和`NtCreateThreadEx`
   1. 利用 `HideFromDebugger` 标志位来对调试器隐藏自身。

### 1.2 SEH、VEH

总的来说，利用 SEH 和 VEH 机制，尝试抛出一些会被调试器处理的中断或异常，同时自己挂一个处理函数，如果异常被调试器捕获了，那自己挂的异常处理函数就不会被调用，借此判断是否有调试器正在调试程序。

1. `TF`标志位和`INT 1`中断
2. `INT 3` 中断和 SEH 处理函数，`__try __except` 或 MinGW 的 `__try1 __except1`，顺便一提我的SEH实验没成功。但是 VEH 基本没问题。
3. `DBG_PRINTEXCEPTION_WIDE_C`和`DBG_PRINTEXCEPTION_W`，Windows 10 `OutputDebugString` 利用了这个 Exception 来抛出调试字符串。
4. `EXCEPTION_INVALID_HANDLE`

### 1.3 调试寄存器

`GetThreadContext` 获取当前上下文，判断 `Dr0`-`Dr3`寄存器的值。

### 1.4 完整性校验

原理是调试器通过临时修改断点处指令为中断来取得程序控制权，可以用CRC校验，或者更简单点，直接逐字节求和，判断代码是否被篡改。

## 0x02 系统API方式

### 2.1 IsDebuggerPresent

首先出场的就是 `IsDebuggerPresent` 这个 API 了，文档[可以在这里](https://docs.microsoft.com/en-us/windows/win32/api/debugapi/nf-debugapi-isdebuggerpresent)找到。简要概述一下这个接口，微软的描述是此函数允许应用程序确定自己是否正在被调试，并依此改变行为。例如通过`OutputDebugString`函数提供更多调试信息。

微软的本意应该是一个调试开关式的东西，正经写过工作代码应该知道代码里加个调试开关方便在出问题的时候拿详细日志是很有用很方便的，同时也能在不需要调试的时候也不会让程序不会损失太多性能。比起编译期的调试开关`_DEBUG`宏之类的会更灵活一些。

扯远了。总之，这个函数没参数，返回`BOOL`，案例很好写。

```c
#include <debugapi.h>

void anti_debug_by_isDebuggerPresent(void) {
  if (IsDebuggerPresent() == TRUE) {
    MessageBoxA(NULL, "debugger detected", "IsDebuggerPresent", MB_OK);
  }
}
```

就是这样。

`IsDebuggerPresent` 这个 API 的实现方式是从 PEB *Process Environment Block* 读取 `BeingDebugged` 字段。随便什么调试器跳转过去就能看到这样的实现代码。

```asm
mov eax, dword ptr fs:[0x30]
movzx eax, byte ptr ds:[eax+0x2]
ret 
```

`fs:[0]`是 TEB *Thread Environment Block* 结构的地址，其中`fs:[0x30]` 这个偏移是 PEB 指针，第一行的意思是将 PEB 指针赋值给 eax 寄存器。

第二行就是从 PEB 结构的 0x2 偏移处，也就是 `BeingDebugged` 字段，取 1 字节，赋值到 eax 。

第三行就是返回了，没有参数和局部变量所以也没平栈，无论 `__cdecl` 还是 `__stdcall` 都是在 `eax` 寄存器保存返回值。

从[wiki](https://en.wikipedia.org/wiki/Win32_Thread_Information_Block) 和 [NTAPI UNDOCUMENTED FUNCTIONS](http://undocumented.ntinternals.net/index.html?page=UserMode%2FUndocumented%20Functions%2FNT%20Objects%2FThread%2FTEB.html) 查询到的文档都能看到 PEB 结构的内存布局。

想要 bypass 这种检查就非常容易，修改 PEB 结构中的 `BeingDebugged` 字段值为 0 就完事了。

### 2.2 NtGlobalFlag

`NtGlobalFlag` 也是一个 PEB 的字段，但是在微软官方的 PEB 结构文档和定义里没有给出这个字段（在 Reserved 里）。查阅上面提到的文档或者用 WinDbg 的 `dt` 命令都可以查到。

当这个字段包含特定标志位（`0x20 | 0x40`，分别是 **FLG_HEAP_ENABLE_TAIL_CHECK** 和 **FLG_HEAP_ENABLE_FREE_CHECK**）的时候提示有调试器存在（[Geoff Chappell, Software Analyst，RtlGetNtGlobalFlags()](https://www.geoffchappell.com/studies/windows/win32/ntdll/api/rtl/regutil/getntglobalflags.htm)，没微软的文档）。

这里给出 WinDbg 查到的字段偏移。微软商店里的 WinDbg Preview 也是一样的。关于 `dt` 命令可以用 `.hh dt` 来查阅命令的文档，`?` 来查阅可用命令，或者直接点上面的帮助。

```plain
0:000> dt _peb NtGlobalFlag @$peb
ntdll!_PEB
   +0x068 NtGlobalFlag : 0x70
```

可以看到偏移是 `0x68`，WinDbg 中标志位的值是 `x70`，符合上面所说的 `0x20|0x40`。接下来尝试实现一下。首先因为我用的 MinGW 所以需要写两句汇编去取PEB指针。（用的 nasm，gcc 的内联汇编语法太怪了）

```asm
section .text
    global _GetPEB

_GetPEB:
    mov eax,[fs:30h]
    retn
```

再具体实现。

```c
void anti_debug_by_RtlGetNtGlobalFlags(void) {
  // 两种方式，直接读内存或者用undocumented接口
  PPEB peb = GetPEB();
  if (*(PULONG)((PBYTE)peb + 0x68) & (0x20 | 0x40)) {
    MessageBoxA(NULL, "debugger detected", "PEB->NtGlobalFlag", MB_OK);
  }
  // 或者...
  HMODULE ntdll = LoadLibraryA("ntdll.dll");
  FARPROC proc = GetProcAddress(ntdll, "RtlGetNtGlobalFlags");
  typedef ULONG (*RtlGetNtGlobalFlags_t)(void);
  if (((RtlGetNtGlobalFlags_t)proc)() & (0x20 | 0x40)) {
    MessageBoxA(NULL, "debugger detected", "RtlGetNtGlobalFlags", MB_OK);
  }
}
```

差别不大，可以根据需要选择其一。编译后不使用调试器打开则不会触发反调试代码。

bypass 这个检查也很容易，因为标志位都在被调试进程的地址空间里，直接改掉就行了。

### 2.3 HEAP->Flags

PEB 结构中还有个指向当前堆信息结构的指针，`ProcessHeap`。可以用 WinDbg 的 `dt` 命令查看。

```plain
0:000> dt _peb processheap @$peb
ntdll!_PEB
   +0x018 ProcessHeap : 0x012d0000 Void
```

而这个 heap 结构的也同样可以用 `dt` 命令查看。我们关注的是 heap 结构中的 `Flags` 和 `ForceFlags` 字段。

```plain
0:000> dt _heap flags 0x012d0000
ntdll!_HEAP
   +0x040 Flags : 0x40000062
0:000> dt _heap forceflags 0x012d0000
ntdll!_HEAP
   +0x044 ForceFlags : 0x40000060
```

当 Flags 没有 `HEAP_GROWABLE` 标志位，或 `ForceFlags` 不为零的时候，则可能存在调试器。同样的， 没有官方的文档，只能说逆向出这些东西的大佬真是太强啦。关于 Flags 谷歌了一下，发现在 [CTF Wiki](https://ctf-wiki.org/reverse/windows/anti-debug/heap-flags/#flags) 有比较详细的说明。我搬一部分过来。

> 在所有版本的 Windows 中, `Flags`字段的值正常情况都设为`HEAP_GROWABLE(2)`, 而`ForceFlags`字段正常情况都设为`0`. 然而对于一个 32 位进程 (64 位程序不会有此困扰), 这两个默认值, 都取决于它的宿主进程(host process) 的 [`subsystem`](https://msdn.microsoft.com/en-us/library/ms933120.aspx)版本 (这里不是指所说的比如 win10 的 linux 子系统). 只有当`subsystem`在`3.51`及更高的版本, 字段的默认值才如前所述. 如果是在`3.10-3.50`版本之间, 则两个字段的`HEAP_CREATE_ALIGN_16 (0x10000)`都会被设置. 如果版本低于`3.10`, 那么这个程序文件就根本不会被运行.
>
> 如果某操作将`Flags`和`ForgeFlags`字段的值分别设为`2`和`0`, 但是却未对`subsystem`版本进行检查, 那么就可以表明该动作是为了隐藏调试器而进行的.

接下来给出案例代码：

```c
void anti_debug_by_PEB_HeapFlags(void) {
  PPEB peb = GetPEB();
  PVOID heap = *(PDWORD)((PBYTE)peb + 0x18);
  PDWORD heapFlags = (PDWORD)((PBYTE)heap + 0x40);
  PDWORD forceFlags = (PDWORD)((PBYTE)heap + 0x44);

  if (*heapFlags & ~HEAP_GROWABLE || *forceFlags != 0) {
    MessageBoxA(NULL, "debugger detected", "PEB->_HEAP->HeapFlags,ForceFlags", MB_OK);
  }
}
```

代码本身很简单，不多解释。在调试器启动时会触发反调试代码，正常运行则不会。这个检查比较粗陋，可以根据上面 CTF Wiki 摘录内容的说法，根据 PE 头中的 subsystem 来二次判断，来发现尝试 bypass 反调试代码的行为。

至于如何 bypass 这个反调试方案，按上面给出的原理来反向应用就好了。

### 2.4 CheckRemoteDebuggerPresent

`CheckRemoteDebuggerPresent` 的[微软文档](https://docs.microsoft.com/en-us/windows/win32/api/debugapi/nf-debugapi-checkremotedebuggerpresent)中这么描述：确定指定进程是否正在被调试。接受两个参数，一个是进程的 HANDLE，一个是 PBOOL。

应用方式可以有很多，可以在进程内自己检查自己有没有被调试；或者开新进程去监视原进程是否正在被调试；甚至注入正常进程，隐藏好自己，再去监视原进程是否被调试；甚至干脆潜伏下来开个后门，亲自人肉监视屏幕上有没有调试器......越说越离谱了。

总之先给了案例。

```c
void anti_debug_by_CheckRemoteDebuggerPresent(void) {
  BOOL isRemoteDebuggerPresent = FALSE;
  if (CheckRemoteDebuggerPresent(GetCurrentProcess(), &isRemoteDebuggerPresent)) {
    if (isRemoteDebuggerPresent == TRUE) {
      MessageBoxA(NULL, "debugger detected", "CheckRemoteDebuggerPresent", MB_OK);
    }
  }
}
```

代码很简单不多解释，不过从这里可以引出新的内容：`CheckRemoteDebuggerPresent` 的实现方式是调用 `NtQueryInformationProcess` ，一个没有文档的内核接口。

### 2.5 NtQueryInformationProcess

`NtQueryInformationProcess` 同样没文档，这里给出比较清晰的 [CTF Wiki](https://ctf-wiki.org/reverse/windows/anti-debug/ntqueryinformationprocess/) 的说明链接。`NtQueryInformationProcess` 是一个查询信息的接口，输入参数包括查询的信息类型、进程HANDLE、结果指针等。用法同样是简单的。

值得关注的查询信息类型包括：

- `ProcessDebugPort`
- `ProcessBasicInformation`
- `ProcessDebugObjectHandle`
- `ProcessDebugFlags`

对于 `ProcessDebugPort`，查询结果是一个 DWORD，当存在调试器时查询结果会是 `0xffffffff`。

```c
void anti_debug_by_NtQueryInformationProcess(void) {
  HMODULE ntdll = LoadLibrary(TEXT("ntdll.dll"));
  if (ntdll == NULL) {
    abort();
  }

  FARPROC ntQueryInfoProc = GetProcAddress(ntdll, "NtQueryInformationProcess");
  if (ntQueryInfoProc == NULL) {
    abort();
  }

  DWORD isDebuggerPresent = FALSE;
  NTSTATUS status = ntQueryInfoProc(GetCurrentProcess(), ProcessDebugPort, &isDebuggerPresent, sizeof(DWORD), NULL);
  if (status == 0 && isDebuggerPresent) {
    MessageBoxA(NULL, "debugger detected", "NtQueryInformationProcess", MB_OK);
    return;
  }
}
```

对于 `ProcessBasicInformation`，查询结果是 `PROCESS_BASIC_INFORMATION` 结构，可以根据这个结构来进一步判断父进程是否是已知的调试器。

```c
#ifdef UNICODE
#  define MY_STRCMP wcscmp
#else
#  define MY_STRCMP strcmp
#endif

void anti_debug_by_NtQueryInformationProcess_BasicInformation(void) {
  HMODULE ntdll = LoadLibrary(TEXT("ntdll.dll"));
  if (ntdll == NULL) {
    abort();
  }

  FARPROC ntQueryInfoProc = GetProcAddress(ntdll, "NtQueryInformationProcess");
  if (ntQueryInfoProc == NULL) {
    abort();
  }

  PROCESS_BASIC_INFORMATION info;
  NTSTATUS status = ntQueryInfoProc(GetCurrentProcess(), ProcessBasicInformation, &info, sizeof(info), NULL);
  if (status == 0) {
    HANDLE hProcSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hProcSnap == NULL) {
      abort();
    }

    PROCESSENTRY32 pe32;
    pe32.dwSize = sizeof(PROCESSENTRY32);
    if (!Process32First(hProcSnap, &pe32)) {
      abort();
    }

    do {
      if (pe32.th32ProcessID == info.InheritedFromUniqueProcessId) {
        if (MY_STRCMP(TEXT("devenv.exe"), pe32.szExeFile) == 0 || MY_STRCMP(TEXT("x32dbg.exe"), pe32.szExeFile) == 0 ||
            MY_STRCMP(TEXT("x64dbg.exe"), pe32.szExeFile) == 0 || MY_STRCMP(TEXT("ollydbg.exe"), pe32.szExeFile) == 0) {
          MessageBoxA(NULL, "debugger detected", "BasicInformation", MB_OK);
          CloseHandle(hProcSnap);
          return;
        }
      }
    } while (Process32Next(hProcSnap, &pe32));
  }
}
```

`ProcessObjectDebugHandle` 和 `ProcessDebugFlags` 就不一一给案例了。检查方式也很简单，就是判断非零则存在调试器。

```c
ntQueryInfoProc(GetCurrentProcess(), ProcessObjectDebugHandle, &handle, sizeof(HANDLE), NULL);
ntQueryInfoProc(GetCurrentProcess(), ProcessDebugFlags, &flags, sizeof(ULONG), NULL);
```

因为 `NtQueryInformationProcess` 是从内核查询消息，所以 bypass 会比较难——就是说需要 HOOK 。但我还不会 HOOK ，所以略过。

### 2.6 NtSetInformationThread

又是一个没有文档的API。`NtSetInformationThread` 等同于 `ZwSetInformationThread`，通过设置 `ThreadHideFromDebugger` 标志位可以禁止线程产生调试事件。如果正处于调试状态执行了这个 API 则会导致程序立即退出。

案例如下。

```c
typedef NTSTATUS(NTAPI *pfnNtSetInformationThread)(_In_ HANDLE ThreadHandle, _In_ ULONG ThreadInformationClass,
                                                   _In_ PVOID ThreadInformation, _In_ ULONG ThreadInformationLength);
void anti_debug_by_HideFromDebugger(void) {
  HMODULE ntdll = LoadLibrary(TEXT("ntdll.dll"));
  if (ntdll == NULL) {
    abort();
  }

  pfnNtSetInformationThread ntSetInfoThread = (pfnNtSetInformationThread)GetProcAddress(ntdll, "NtSetInformationThread");
  if (ntSetInfoThread == NULL) {
    abort();
  }

  ntSetInfoThread(GetCurrentThread(), ThreadHideFromDebugger, NULL, 0);
  // ... NtCreateThreadEx THREAD_CREATE_FLAGS_HIDE_FROM_DEBUGGER
}
```

同样因为这一方式是走内核接口，可以通过 HOOK 技术把相应的标志位拦截掉就行。

### 2.7 Set/GetLastError

对`SetLastError`和`GetLastError`的利用方式是结合 `OutputDebugString` 失败时会修改 `GetLastError()` 的错误码的行为，判断是否有调试器存在。

```c
// TODO: somehow not work on windows 10, need more test.
void anti_debug_by_SetLastError(void) {
  SetLastError(0x1234);
  OutputDebugString(TEXT("Hello Debugger!"));
  if (GetLastError() == 0x1234) {
    MessageBoxA(NULL, "debugger detected", "Set/Get LastError", MB_OK);
  }
}
```

比较奇怪的是在我这无论在不在调试环境跑都会触发反调试，环境 Windows 10 + MinGW 。

## 0x03 异常处理方式

异常处理方式的反调试，是通过触发会被调试器处理的中断或者异常，如果调试器拦截并处理了中断或异常，就会导致程序里注册的异常处理函数未被执行，进而发现正在被调试。

这个思路也可以用来构造特殊的控制流，比如把关键逻辑放在中断处理函数里，然后抛出 INT 1 中断（单步执行），如果被调试器命中，则我们构造的控制流就会被破坏，程序就会跑飞。

### 3.1 INT 1

INT 1 中断的含义是 SINGLE STEP，在调试器上的表现就是会让调试器断在中断的位置（反正在x32dbg上的表现是这样）。INT 1中断后，如果没有调试器，那么控制权会转交给调试器，SEH 不会执行，反之则 SEH 执行，用户程序保留控制权。

实际上发现 x32dbg 即使断到了也会把控制权转给 SEH，所以对关于 SEH 反调试是否可行、如何实现持疑问。但是经过一番搜索和研究发现 VEH 机制可以实现上述逻辑。案例代码如下。

用来抛出 INT 1 中断的汇编代码

```asm
section .text
	global _RaiseInt1

_RaiseInt1:
    pushfd
    or [esp],dword 0x100
    popfd
    retn
```

检测调试器的函数如下

```c
BOOL volatile VEH_INT1_isDebuggerPresent = FALSE;

LONG CALLBACK VEH_INT1_UnhandledExceptionFilter(_In_ EXCEPTION_POINTERS *lpEP) {
  switch (lpEP->ExceptionRecord->ExceptionCode) {
  case EXCEPTION_SINGLE_STEP:
    // handle single step exception if not handled by debugger
    VEH_INT1_isDebuggerPresent = FALSE;
    return EXCEPTION_CONTINUE_EXECUTION;
  default:
    return EXCEPTION_CONTINUE_SEARCH;
  }
}

void anti_debug_by_VEH_INT1(void) {
  VEH_INT1_isDebuggerPresent = TRUE;
  // https://docs.microsoft.com/en-us/windows/win32/api/errhandlingapi/nf-errhandlingapi-setunhandledexceptionfilter
  SetUnhandledExceptionFilter(VEH_INT1_UnhandledExceptionFilter);
  // https://docs.microsoft.com/zh-cn/windows/win32/api/errhandlingapi/nf-errhandlingapi-addvectoredexceptionhandler?redirectedfrom=MSDN
  // https://docs.microsoft.com/en-us/windows/win32/api/winnt/nc-winnt-pvectored_exception_handler
  RaiseInt1();
  if (VEH_INT1_isDebuggerPresent == TRUE) {
    MessageBoxA(NULL, "debugger detected", "VEH INT1", MB_OK);
  }
}
```

利用 `SetUnhandledExceptionFilter` 实现，文档链接在注释里给出了。也可以再罗嗦一点，结合 `AddVectoredExceptionHandler` 实现。但逻辑还是那样。

INT 1中断方式检测调试器后，可以恢复到正常控制流执行。但是 INT 3 会有所区别，INT 3 中断时 EIP 会停留在中断指令处，中断处理中需要修改 EIP 的值恢复控制流。

关于 SEH 中断反调试我留个链接：[看雪论坛：基于SEH的静态反调试实例分析](https://bbs.pediy.com/thread-267324.htm)，有空再分析看看。

### 3.2 INT 3

INT 3 中断就是 `0xcc` 一字节中断指令，顺便一提啊，因为VC会用 0xcc 填充未初始化的栈，用C写过代码多少都见过的 *烫烫烫* 错误就是来自于此。

参考 [CTF Wiki - Interrupt 3](https://ctf-wiki.org/reverse/windows/anti-debug/int-3/)。

> 当`EXCEPTION_BREAKPOINT(0x80000003)`异常触发时, Windows 会认定这是由单字节的 "`CC`" 操作码 (也即`Int 3`指令) 造成的. Windows 递减异常地址以指向所认定的 "`CC`" 操作码, 随后传递该异常给异常处理句柄. 但是 EIP 寄存器的值并不会发生变化.
>
> 因此, 如果使用了 `CD 03`（这是 `Int 03` 的机器码表示），那么当异常处理句柄接受控制时, 异常地址是指向 `03` 的位置.

这里有一个调试中发现的怪异问题：调试器内运行时会平栈错误，esp 会越过原本的返回地址，导致执行到 ret 时返回地址是0，产生异常。目前不确定是不是因为上面说的EIP没有+1导致的问题。

案例代码如下。

```asm
section .text
	global _RaiseInt3

_RaiseInt3:
	int 3
	retn
```

```c
BOOL volatile VEH_INT3_isDebuggerPresent = FALSE;

LONG CALLBACK VEH_INT3_UnhandledExceptionFilter(_In_ EXCEPTION_POINTERS *lpEP) {
  switch (lpEP->ExceptionRecord->ExceptionCode) {
  case EXCEPTION_BREAKPOINT:
    // handle single step exception if not handled by debugger
    VEH_INT3_isDebuggerPresent = FALSE;
    lpEP->ContextRecord->Eip += 1;
    return EXCEPTION_CONTINUE_EXECUTION;
  default:
    return EXCEPTION_CONTINUE_SEARCH;
  }
}

void anti_debug_by_VEH_INT3(void) {
  VEH_INT3_isDebuggerPresent = TRUE;
  SetUnhandledExceptionFilter(VEH_INT3_UnhandledExceptionFilter);
  RaiseInt3();
  if (VEH_INT3_isDebuggerPresent == TRUE) {
    MessageBoxA(NULL, "debugger detected", "SEH INT3", MB_OK);
  }
}
```

可以看到和 INT1 的案例别无二致。这里再附带上汇编结果，大佬也可以看看上面说的平栈问题是怎么回事。编译好的案例会附在最末。

```asm
sub esp, 0x1C
mov dword ptr ds:[0x5B4000], 0x1
mov dword ptr ss:[esp], <packed.sub_5B1390>
call dword ptr ds:[<&_SetUnhandledExceptionFilterStub@4>]
sub esp, 0x4
call packed.5B1AA1 ; int3, retn
mov eax, dword ptr ds:[0x5B4000]
cmp eax, 0x1
je packed.5B1650
add esp, 0x1C
ret 
mov dword ptr ss:[esp+0xC], 0x0
mov dword ptr ss:[esp+0x8], packed.5B20A1
mov dword ptr ss:[esp+0x4], packed.5B202A
mov dword ptr ss:[esp], 0x0
call dword ptr ds:[<&MessageBoxA>]
sub esp, 0x10
add esp, 0x1C
ret 
```

### 3.3 DebugOutputString

利用方式和前面一样。

```c
// TODO: NOT WORK

BOOL VEH_OutputDebugStringException_isDebugPresent = FALSE;

LONG CALLBACK VEH_OutputDebugStringException_UnhandledExceptionFilter(_In_ EXCEPTION_POINTERS *lpEP) {
  switch (lpEP->ExceptionRecord->ExceptionCode) {
  case EXCEPTION_BREAKPOINT:
    // handle single step exception if not handled by debugger
    VEH_INT3_isDebuggerPresent = FALSE;
    return EXCEPTION_CONTINUE_EXECUTION;
  default:
    return EXCEPTION_CONTINUE_SEARCH;
  }
}

void anti_debug_by_VEH_OutputDebugException(void) {
  ULONG_PTR args[4] = {0, 0, 0, 0};
  args[0] = (ULONG_PTR)wcslen(L"debug") + 1;
  args[1] = (ULONG_PTR)L"debug";
  AddVectoredExceptionHandler(0, VEH_OutputDebugStringException_UnhandledExceptionFilter);
  VEH_OutputDebugStringException_isDebugPresent = TRUE;
  RaiseException(DBG_PRINTEXCEPTION_WIDE_C, 0, 4, args);
  RemoveVectoredExceptionHandler(VEH_OutputDebugStringException_UnhandledExceptionFilter);
  if (VEH_OutputDebugStringException_isDebugPresent == TRUE) {
    MessageBoxA(NULL, "debugger detected", "OutputDebugString", MB_OK);
  }
}
```

实测发现 x32dbg 并不会处理 `DBG_PRINTEXCEPTION_WIDE_C` ，所以这个反调试对 x32dbg 没用。

### 3.4 INVALID_HANDLE

根据微软的文档 [CloseHandle function (handleapi.h)](https://docs.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-closehandle) 说明：

> If the application is running under a debugger, the function will throw an exception if it receives either a handle value that is not valid or a pseudo-handle value. This can happen if you close a handle twice, or if you call **CloseHandle** on a handle returned by the [FindFirstFile](https://docs.microsoft.com/en-us/windows/desktop/api/fileapi/nf-fileapi-findfirstfilea) function instead of calling the [FindClose](https://docs.microsoft.com/en-us/windows/desktop/api/fileapi/nf-fileapi-findclose) function.

可以得知，在调试器启动时，`CloseHandle` 关闭无效的 `HANDLE` 时会出现 `EXCEPTION_INVALID_HANDLE` 异常。所以只要故意关闭一个无效的 `HANDLE`，抓住这个异常，就能确定调试器存在。

```c
LONG CALLBACK VEH_INVALID_HANDLE_UnhandledExceptionFilter(_In_ EXCEPTION_POINTERS *lpEP) {
  switch (lpEP->ExceptionRecord->ExceptionCode) {
  case EXCEPTION_INVALID_HANDLE:
    // if debug present
    MessageBoxA(NULL, "debugger detected", "INVALID HANDLE", MB_OK);
    return EXCEPTION_CONTINUE_EXECUTION;
  default:
    return EXCEPTION_CONTINUE_SEARCH;
  }
}

void anti_debug_by_VEH_INVALID_HANDLE(void) {
  AddVectoredExceptionHandler(0, VEH_INVALID_HANDLE_UnhandledExceptionFilter);
  CloseHandle((HANDLE)0xBAAD);
  RemoveVectoredExceptionHandler(VEH_INVALID_HANDLE_UnhandledExceptionFilter);
}
```

和之前的检查不同，INVALID_HANDLE 是 **出现这个异常才存在调试器**，之前的异常处理方式都是没出现异常才存在调试器。

## 0x04 硬件断点

[x86 体系上存在一套调试寄存器](https://en.wikipedia.org/wiki/X86_debug_register)，就是 `dr0`-`dr7`这8个寄存器。其中`dr0`-`dr3`保存的硬件断点的线性地址，断点条件保存在`dr7`寄存器。`dr6`寄存器保存的是调试状态，指示触发了哪个断点条件。

所以发现硬件断点的存在，就可以百分百确定正在被调试。

### 4.1 硬件断点

直接给案例代码。

```c
// detect hardware breakpoint
void anti_debug_by_DebugRegister(void) {
  CONTEXT ctx;
  ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;
  if (GetThreadContext(GetCurrentThread(), &ctx)) {
    if (ctx.Dr0 != 0 || ctx.Dr1 != 0 || ctx.Dr2 != 0 || ctx.Dr3 != 0) {
      MessageBoxA(NULL, "debugger detected", "Dr0-Dr3", MB_OK);
    }
  }
}
```

通过`GetThreadContext`这个接口获得当前寄存器状态，当然也可以通过内联汇编来实现。当发现四个断点寄存器非零就可以确定正在被调试了。

## 0x05 完整性校验

完整性校验反调试的原理是检测 `0xCC` 软件断点，当我们一般说的在程序里*下断点*的时候下的是软件断点，实现的原理是调试器在这个内存位置上临时放一个`0xcc`占位，当EIP走到这里时会触发一个INT 3中断，调试器趁机取得控制权。同时因为 INT 3 断点不会把 EIP + 1，所以调试器只需要把改成 `0xcc` 的地方改回去，就可以让程序继续跑而无需去碰寄存器。

### 5.1 SoftwareBreakpoint

下面的案例给了一个简单的软件断点检测，只能检测到下在函数开头的软件断点。

```c
// detect 0xcc interrupt code
void anti_debug_by_SoftwareBreakPoint(PBYTE addr) {
  if (*addr == 0xcc) {
    MessageBoxA(NULL, "debugger detected", "SoftwareBreakpoint", MB_OK);
  }
}

// 在主函数里：
// anti_debug_by_SoftwareBreakPoint((PBYTE)&load_PE)
// 就能检测到在 load_PE 函数开头处下的断点
```

如果能以一定的方式确定一个函数的代码段大小，也可以做到对整个函数的完整性检测（通过计算 CRC 或者其他哈希算法，甚至就直接累加都行）。

确定函数代码段大小的方式我只想到一个利用栈上的返回地址=，=在函数开头和结尾部分调用一次获取栈上返回地址的函数就能拿到一个范围了，但感觉并不可靠，主要是编译器优化可能重排代码，而且不走到结尾部分也没法开始计算哈希=，=这都给人调试完了。

## 结论

所有案例代码都在这里：[github.com/nnnewb/learning-packer]([learning-packer/packer6 at main · nnnewb/learning-packer (github.com)](https://github.com/nnnewb/learning-packer/tree/main/packer6))

总结就是反调试主要靠 *判断调试器特征* 来发现正在被调试。而这个判断方法就很多，从硬件到操作系统层面，再到软件层面，都有洞可以钻。

总结这篇里实践的反调试（或者说检测调试器）方式有这些：

- PEB和相关结构的各种标志位
- 内核接口，`NtQueryInformationProcess`、`NtSetInformationThread`等等
- 异常处理机制，`SEH`，`VEH`，触发会被调试器处理的异常（或者只在有调试器时才会触发的异常）来发现调试器
- 调试寄存器和硬件断点
- 代码完整性校验发现软件断点

以上就是本篇实验过的所有反调试思路了。原本应该有个通过 TLS 回调隐藏自身的案例，但是 MinGW 加不了 TLS 回调（可能还是我菜），谷歌搜到的做法都是要对编译好的二进制文件打补丁，太麻烦就没搞。

另外还有个利用执行时间做反调试，因为不知道现在都是怎么利用，然后是这个反调试原理感觉也是很简单=，=就是利用方法可能千奇百怪，单单写两次 time 调用感觉没啥意义就没写（偷懒了）。

总之就是隐藏好反调试的代码，然后发现调试器就悄悄施展迷惑手段或者干脆大搞破坏。

## 参考资料

- [Anti Debugging Protection Techniques With Examples](https://www.apriorit.com/dev-blog/367-anti-reverse-engineering-protection-techniques-to-use-before-releasing-software)
- [Geoff Chappell, Software Analyst](https://www.geoffchappell.com/)
- [CTF Wiki](https://ctf-wiki.org/)
- [《恶意代码分析实战》](https://book.douban.com/subject/25868289/)

内容主要来自第一个链接，根据我的环境做了一些修改（比如有些SEH的我实测 x32dbg 不行就换成了VEH），结合参考了 CTF wiki 和 《恶意代码分析实战》这书。API 全是微软的文档和没有文档化的接口我不一个一个摆链接了。
