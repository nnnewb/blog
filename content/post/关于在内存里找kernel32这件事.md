---
title: 关于在内存里找kernel32这件事
slug: find-kernel32-in-memory
date: 2021-10-14 16:31:00
categories:
- 逆向
tags:
- 汇编
- 逆向
- Windows
---

## 前言

总得有个前言。

用 nasm 手工打造了一个 PE 文件后，这个 PE 文件还没什么卵用。如果要动 IAT，又嫌麻烦。网上冲浪找到[一篇关于 shellcode 的文章](https://www.ired.team/offensive-security/code-injection-process-injection/finding-kernel32-base-and-function-addresses-in-shellcode#finding-kernel32-base-address)，讲如何在内存里找到 kernel32.dll 并调用 WinExec 函数，于是就想实践一下看看，实际抄代码碰到不少坑。对汇编又熟悉了一点。

## 0x01 寻找 kernel32

微软有一篇很[简短的文章](https://docs.microsoft.com/en-us/windows/win32/debug/thread-environment-block--debugging-notes-)。

> The Thread Environment Block ([**TEB structure**](https://docs.microsoft.com/en-us/windows/win32/api/winternl/ns-winternl-teb)) holds context information for a thread.
>
> In the following versions of Windows, the offset of the 32-bit TEB address within the 64-bit TEB is 0. This can be used to directly access the 32-bit TEB of a WOW64 thread. This might change in later versions of Windows

另外在[维基百科页面](https://en.wikipedia.org/wiki/Win32_Thread_Information_Block)也有一点概述，*TIB* 就是 *TEB* 。*TIB* 全称是 *Thread Information Block* ，*TEB* 是 *Thread Environment Block* 。

关于 *TIB* 和 *TEB* 的微软官方文档和文章链接很多都失效了，能找到的相关信息不多。但是微软至少还[给出了 TEB 的结构定义](https://docs.microsoft.com/en-us/windows/win32/api/winternl/ns-winternl-teb)吧（在Windows SDK 里）。

```c++
typedef struct _TEB {
  PVOID Reserved1[12];
  PPEB  ProcessEnvironmentBlock;
  PVOID Reserved2[399];
  BYTE  Reserved3[1952];
  PVOID TlsSlots[64];
  BYTE  Reserved4[8];
  PVOID Reserved5[26];
  PVOID ReservedForOle;
  PVOID Reserved6[4];
  PVOID TlsExpansionSlots;
} TEB, *PTEB;
```

大量的刺眼的 `Reserved` 。不过还好，花了点时间还是谷歌出了所谓的`Undocumented`的相关信息。[NTAPI Undocumented Function](http://undocumented.ntinternals.net/index.html?page=UserMode%2FUndocumented%20Functions%2FNT%20Objects%2FThread%2FTEB.html)。也可以像我看的那篇文章一样，用 `WinDbg Preview` 去实际看看内存里的结构。

```c++
typedef struct _TEB {
  NT_TIB                  Tib;
  PVOID                   EnvironmentPointer;
  CLIENT_ID               Cid;
  PVOID                   ActiveRpcInfo;
  PVOID                   ThreadLocalStoragePointer;
  PPEB                    Peb;
  ULONG                   LastErrorValue;
  ULONG                   CountOfOwnedCriticalSections;
  PVOID                   CsrClientThread;
  PVOID                   Win32ThreadInfo;
  ULONG                   Win32ClientInfo[0x1F];
  PVOID                   WOW32Reserved;
  ULONG                   CurrentLocale;
  ULONG                   FpSoftwareStatusRegister;
  PVOID                   SystemReserved1[0x36];
  PVOID                   Spare1;
  ULONG                   ExceptionCode;
  ULONG                   SpareBytes1[0x28];
  PVOID                   SystemReserved2[0xA];
  ULONG                   GdiRgn;
  ULONG                   GdiPen;
  ULONG                   GdiBrush;
  CLIENT_ID               RealClientId;
  PVOID                   GdiCachedProcessHandle;
  ULONG                   GdiClientPID;
  ULONG                   GdiClientTID;
  PVOID                   GdiThreadLocaleInfo;
  PVOID                   UserReserved[5];
  PVOID                   GlDispatchTable[0x118];
  ULONG                   GlReserved1[0x1A];
  PVOID                   GlReserved2;
  PVOID                   GlSectionInfo;
  PVOID                   GlSection;
  PVOID                   GlTable;
  PVOID                   GlCurrentRC;
  PVOID                   GlContext;
  NTSTATUS                LastStatusValue;
  UNICODE_STRING          StaticUnicodeString;
  WCHAR                   StaticUnicodeBuffer[0x105];
  PVOID                   DeallocationStack;
  PVOID                   TlsSlots[0x40];
  LIST_ENTRY              TlsLinks;
  PVOID                   Vdm;
  PVOID                   ReservedForNtRpc;
  PVOID                   DbgSsReserved[0x2];
  ULONG                   HardErrorDisabled;
  PVOID                   Instrumentation[0x10];
  PVOID                   WinSockData;
  ULONG                   GdiBatchCount;
  ULONG                   Spare2;
  ULONG                   Spare3;
  ULONG                   Spare4;
  PVOID                   ReservedForOle;
  ULONG                   WaitingOnLoaderLock;
  PVOID                   StackCommit;
  PVOID                   StackCommitMax;
  PVOID                   StackReserved;
} TEB, *PTEB;
```

不过依然没什么卵用，因为在乎的只有 PPEB 这个字段。好吧，点到为止。

在那篇文章的原文里，给出的找到 kernel32.dll 的查找路径是这样的：`TEB->PEB->Ldr->InMemoryOrderLoadList->currentProgram->ntdll->kernel32.BaseDll`

### 1.1  Process Environment Block

从 TEB 出发，找到 PEB `(12*sizeof PVOID)==48==0x30` 。PEB 的结构如下，文档参考[这个](http://undocumented.ntinternals.net/index.html?page=UserMode%2FUndocumented%20Functions%2FNT%20Objects%2FProcess%2FPEB.html)。

```c++
typedef struct _PEB {
  BOOLEAN                 InheritedAddressSpace;
  BOOLEAN                 ReadImageFileExecOptions;
  BOOLEAN                 BeingDebugged;
  BOOLEAN                 Spare;
  HANDLE                  Mutant;
  PVOID                   ImageBaseAddress;
  PPEB_LDR_DATA           LoaderData;
  PRTL_USER_PROCESS_PARAMETERS ProcessParameters;
  PVOID                   SubSystemData;
  PVOID                   ProcessHeap;
  PVOID                   FastPebLock;
  PPEBLOCKROUTINE         FastPebLockRoutine;
  PPEBLOCKROUTINE         FastPebUnlockRoutine;
  ULONG                   EnvironmentUpdateCount;
  PPVOID                  KernelCallbackTable;
  PVOID                   EventLogSection;
  PVOID                   EventLog;
  PPEB_FREE_BLOCK         FreeList;
  ULONG                   TlsExpansionCounter;
  PVOID                   TlsBitmap;
  ULONG                   TlsBitmapBits[0x2];
  PVOID                   ReadOnlySharedMemoryBase;
  PVOID                   ReadOnlySharedMemoryHeap;
  PPVOID                  ReadOnlyStaticServerData;
  PVOID                   AnsiCodePageData;
  PVOID                   OemCodePageData;
  PVOID                   UnicodeCaseTableData;
  ULONG                   NumberOfProcessors;
  ULONG                   NtGlobalFlag;
  BYTE                    Spare2[0x4];
  LARGE_INTEGER           CriticalSectionTimeout;
  ULONG                   HeapSegmentReserve;
  ULONG                   HeapSegmentCommit;
  ULONG                   HeapDeCommitTotalFreeThreshold;
  ULONG                   HeapDeCommitFreeBlockThreshold;
  ULONG                   NumberOfHeaps;
  ULONG                   MaximumNumberOfHeaps;
  PPVOID                  *ProcessHeaps;
  PVOID                   GdiSharedHandleTable;
  PVOID                   ProcessStarterHelper;
  PVOID                   GdiDCAttributeList;
  PVOID                   LoaderLock;
  ULONG                   OSMajorVersion;
  ULONG                   OSMinorVersion;
  ULONG                   OSBuildNumber;
  ULONG                   OSPlatformId;
  ULONG                   ImageSubSystem;
  ULONG                   ImageSubSystemMajorVersion;
  ULONG                   ImageSubSystemMinorVersion;
  ULONG                   GdiHandleBuffer[0x22];
  ULONG                   PostProcessInitRoutine;
  ULONG                   TlsExpansionBitmap;
  BYTE                    TlsExpansionBitmapBits[0x80];
  ULONG                   SessionId;
} PEB, *PPEB;
```

接着从 PEB 找到 `Ldr`，位置是 `(sizeof(BOOLEAN)*4+sizeof(HANDLE)+sizeof(PVOID))==12==0xc`。

### 1.2 PEB_LDR_DATA

接着从 `PEB_LDR_DATA` 结构里找 `InMemoryOrderModuleList` 这个字段，`PEB_LDR_DATA` 结构如下。

```c++
typedef struct _PEB_LDR_DATA {
  ULONG                   Length;
  BOOLEAN                 Initialized;
  PVOID                   SsHandle;
  LIST_ENTRY              InLoadOrderModuleList;
  LIST_ENTRY              InMemoryOrderModuleList;
  LIST_ENTRY              InInitializationOrderModuleList;
} PEB_LDR_DATA, *PPEB_LDR_DATA;
```

找到`InMemoryOrderModuleList`字段，位置是`(sizeof(ULONG)+sizeof(BOOLEAN)+sizeof(PVOID)+sizeof(LIST_ENTRY))==20==0x14`

注意 `sizeof(BOOLEAN)` 是 `BYTE` 类型，但这个结构体是被对齐到了4字节的，所以 BOOLEAN 字段后面实际有3个字节的 padding。合起来就是三个 DWORD 。

### 1.3 LDR_DATA_TABLE_ENTRY

之后就是 LIST_ENTRY 这个结构了，用 WinDbg 查了下结构：

```plain
0:000> dt _LIST_ENTRY
ntdll!_LIST_ENTRY
   +0x000 Flink            : Ptr32 _LIST_ENTRY
   +0x004 Blink            : Ptr32 _LIST_ENTRY
```

根据上面 *Undocumented* 文档和原文章的叙述来看，这应该就是个指向 `_LDR_DATA_TABLE_ENTRY` 结构（双向链表）的指针。`_LIST_ENTRY`结构本身是包含两个指针，一个`Forward`正向指针，一个`Backward`。所以我们取`Flink`字段就可以，跳过`InLoadOrderModuleList`这个字段后，一共偏移 `0x14` 就是我们要的 `Flink` 指针了，指向的应该是 `_LDR_DATA_TABLE_ENTRY` 这个结构体中的 `InMemoryOrderLinks` 字段。下面给出`_LDR_DATA_TABLE_ENTRY`的结构（WinDbg）。

```plain
0:000> dt _ldr_data_table_entry
ntdll!_LDR_DATA_TABLE_ENTRY
   +0x000 InLoadOrderLinks : _LIST_ENTRY
   +0x008 InMemoryOrderLinks : _LIST_ENTRY
   +0x010 InInitializationOrderLinks : _LIST_ENTRY
   +0x018 DllBase          : Ptr32 Void
   +0x01c EntryPoint       : Ptr32 Void
   +0x020 SizeOfImage      : Uint4B
   +0x024 FullDllName      : _UNICODE_STRING
   +0x02c BaseDllName      : _UNICODE_STRING
   +0x034 FlagGroup        : [4] UChar
   +0x034 Flags            : Uint4B
   +0x034 PackagedBinary   : Pos 0, 1 Bit
   +0x034 MarkedForRemoval : Pos 1, 1 Bit
   +0x034 ImageDll         : Pos 2, 1 Bit
   +0x034 LoadNotificationsSent : Pos 3, 1 Bit
   +0x034 TelemetryEntryProcessed : Pos 4, 1 Bit
   +0x034 ProcessStaticImport : Pos 5, 1 Bit
   +0x034 InLegacyLists    : Pos 6, 1 Bit
   +0x034 InIndexes        : Pos 7, 1 Bit
   +0x034 ShimDll          : Pos 8, 1 Bit
   +0x034 InExceptionTable : Pos 9, 1 Bit
   +0x034 ReservedFlags1   : Pos 10, 2 Bits
   +0x034 LoadInProgress   : Pos 12, 1 Bit
   +0x034 LoadConfigProcessed : Pos 13, 1 Bit
   +0x034 EntryProcessed   : Pos 14, 1 Bit
   +0x034 ProtectDelayLoad : Pos 15, 1 Bit
   +0x034 ReservedFlags3   : Pos 16, 2 Bits
   +0x034 DontCallForThreads : Pos 18, 1 Bit
   +0x034 ProcessAttachCalled : Pos 19, 1 Bit
   +0x034 ProcessAttachFailed : Pos 20, 1 Bit
   +0x034 CorDeferredValidate : Pos 21, 1 Bit
   +0x034 CorImage         : Pos 22, 1 Bit
   +0x034 DontRelocate     : Pos 23, 1 Bit
   +0x034 CorILOnly        : Pos 24, 1 Bit
   +0x034 ChpeImage        : Pos 25, 1 Bit
   +0x034 ReservedFlags5   : Pos 26, 2 Bits
   +0x034 Redirected       : Pos 28, 1 Bit
   +0x034 ReservedFlags6   : Pos 29, 2 Bits
   +0x034 CompatDatabaseProcessed : Pos 31, 1 Bit
   +0x038 ObsoleteLoadCount : Uint2B
   +0x03a TlsIndex         : Uint2B
   +0x03c HashLinks        : _LIST_ENTRY
   +0x044 TimeDateStamp    : Uint4B
   +0x048 EntryPointActivationContext : Ptr32 _ACTIVATION_CONTEXT
   +0x04c Lock             : Ptr32 Void
   +0x050 DdagNode         : Ptr32 _LDR_DDAG_NODE
   +0x054 NodeModuleLink   : _LIST_ENTRY
   +0x05c LoadContext      : Ptr32 _LDRP_LOAD_CONTEXT
   +0x060 ParentDllBase    : Ptr32 Void
   +0x064 SwitchBackContext : Ptr32 Void
   +0x068 BaseAddressIndexNode : _RTL_BALANCED_NODE
   +0x074 MappingInfoIndexNode : _RTL_BALANCED_NODE
   +0x080 OriginalBase     : Uint4B
   +0x088 LoadTime         : _LARGE_INTEGER
   +0x090 BaseNameHashValue : Uint4B
   +0x094 LoadReason       : _LDR_DLL_LOAD_REASON
   +0x098 ImplicitPathOptions : Uint4B
   +0x09c ReferenceCount   : Uint4B
   +0x0a0 DependentLoadFlags : Uint4B
   +0x0a4 SigningLevel     : UChar
```

要注意到 `_LDR_DATA_TABLE_ENTRY` 结构中的 `InMemoryOrderLinks` 并不是在结构开头，所以取得的地址必须先减去这个偏移值（8字节）再转换类型才是正确的结构。

### 1.4 模块基址

接着从 WinDbg 可以实际发现，这个链表里，我们的程序之后就是`ntdll.dll`，再之后就是`kernel32.dll`，不再演示。反正就当`kernel32.dll`固定在这个链表的第三个元素就是了。真要高鲁棒性的话就得遍历这个链表，按名字找出 `kernel32.dll` 对应的结构，再取地址——麻烦死了。

取得 `kernel32.dll` 对应的 `_LDR_DATA_TABLE_ENTRY` 结构后，就可以提取其中的 `DllBase` 字段了，这个字段就是 `kernel32.dll` 的基址。

### 1.5 TEB 的位置

谷歌一下不难找到，Win32程序进程地址空间里，TEB的地址就在 `[fs:0]` 这个地址上。

### 1.6 获取 kernel 32 基址

那就开始写汇编。

```asm
section .text
    global _main
_main:
    push ebp
    mov ebp,esp

    ; 获取 kernel32.dll 基址
    mov eax, [fs:30h]           ; eax = TEB->PEB
    mov eax, [eax+0ch]          ; eax = PEB->Ldr
    mov eax, [eax+14h]          ; eax = PEB_LDR_DATA->InMemoryOrderModuleList.Flink (当前程序)
    mov eax, [eax]              ; eax = &_LDR_DATA_TABLE_ENTRY.InMemoryOrderModuleList.Flink (现在是 ntdll.dll)
    mov eax, [eax]              ; eax = &_LDR_DATA_TABLE_ENTRY.InMemoryOrderModuleList.Flink (现在是 kernel32.dll)
    mov eax, [eax-8h+18h]       ; eax = &_LDR_DATA_TABLE_ENTRY.DllBase (kernel32.dll 基址)

    xor eax,eax
    pop ebp
    retn
```

用 MinGW 编译。

```shell
nasm main.asm -f win32 -o main.o
gcc main.o -nostartfiles -nodefaultlibs -o main.exe
```

第一步 `[fs:30h]` 这个地址就是 TEB 中的 PEB 指针，将指针保存的地址移入 `eax` 寄存器。现在 `eax` 寄存器指向的就是 PEB 结构了。

第二步取 `PEB->Ldr` 指针。

第三步取 `PEB_LDR_DATA->InMemoryOrderModuleList.Flink` 指针，这个指针指向的是当前程序的 `_LDR_DATA_TABLE_ENTRY.InMemoryOrderModuleList.Flink` 。此时我们已经开始遍历链表。

第四步是取链表的下一个元素，我们认为是 `ntdll.dll` ，再取下一个元素，得到 `kernel32.dll`。

此时的 `eax` 指向的还是 `_LDR_DATA_TABLE_ENTRY.InMemoryOrderModuleList.Flink` 请注意，计算偏移的时候要先移回结构的首部（`-0x08`）再计算。

第五步就是从 `kernel32.dll` 的 `_LDR_DATA_TABLE_ENTRY` 结构里，取 `DllBase` 字段的值了。`eax - 8h + 18h` 得到 `DllBase` 字段的偏移地址，执行后得到的就是 `kernel32.dll` 的基址指针了。

我们可以用 WinDbg Preview 验证下。

....

不知道为啥 WinDbg Preview 不能正确调试，还是用回 x32dbg 。

![image-20211014143628806](image/关于在内存里找kernel32这件事/image-20211014143628806.png)

注意此时 EAX 的值是 `75B30000` ，内容被调试器识别为 `MZ?` ，显然是个 DOS 文件头。

![image-20211014143759203](image/关于在内存里找kernel32这件事/image-20211014143759203.png)

在调试器的内存布局窗口可以看到，这个地址正好就是 `kernel32.dll` 的镜像基址。

到此，我们已经找到了 `kernel32.dll` 的镜像基址，找到了镜像基址后，根据之前学习的对 PE 文件格式的了解，就有机会自己解析导出表，调用 `kernel32.dll` 内的函数啦。

## 0x02 寻找 WinExec 函数

作为实践的目标，这次希望在 `kernel32.dll` 里找出 `WinExec` 函数。这个函数的文档在[这里](https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-winexec)。函数签名如下。

```c++
UINT WinExec(
  [in] LPCSTR lpCmdLine,
  [in] UINT   uCmdShow
);
```

文档说我们应该用 `CreateProcess` 但是那个函数参数多的一批，狗都不看。微软就没点13数么。

### 2.1 寻找导出表

有了 `kernel32.dll` 的基址，下一步就是寻找导出表的位置了。

依据我们对 PE 文件格式的了解，首先得在 Data Directories 里找到 *Export Directory* 。

在此之前，我们先暂存一下 `kernel32.dll` 基址以备后用。

```asm
	mov ebx, eax
```

然后开始寻找 dos 文件头里的 `lfanew` 。相对文件头的偏移是 `3ch` ，内容是相对文件头的偏移值，我们这样计算。

```asm
	mov eax, [ebx+3ch]
	add eax, ebx
```

现在 eax 指向的就是 pe 文件头了。

然后我们找到 `ExportDirectory.VirtualAddress` 的偏移，它在相对 PE 文件头 `78h` 偏移的地方。如果还记得 16 个元素的 Data Directories 结构的话，提醒下 ExportDirectory 就是所有 Data Directories 里排第一个的结构。

```asm
    mov eax, [eax+78h]                                  ; eax = ExportDirectory.VirtualAddress
```

得到的是 RVA ，加上基址。

```asm
    add eax, ebx                                        ; eax = &ExportDirectoryTable
```

接下来要开始解析 ExportDirectoryTable 结构了，参考[微软的文档](https://docs.microsoft.com/en-us/windows/win32/debug/pe-format#export-directory-table)。

因为需要暂存很多变量，我们先给这些变量在栈上分配空间。

### 2.2 分配栈变量

先回到开头，定义好栈如何分配。

```asm
%define kernel32_base 0x04
%define numberof_export_entries 0x08
%define address_of_ordinal_table 0x0c
%define address_of_func_address_table 0x10
%define address_of_export_directory_table 0x14
%define address_of_name_table 0x18
%define ordinal_base 0x1c
```

然后在入口点处，添加 `sub esp, 0x1c`，分配栈空间。之后就可以使用 `[ebp-变量]` 的形式来使用这些变量了。修改后的代码如下。

```asm
%define kernel32_base 0x04
%define numberof_export_entries 0x08
%define address_of_ordinal_table 0x0c
%define address_of_func_address_table 0x10
%define address_of_export_directory_table 0x14
%define address_of_name_table 0x18
%define ordinal_base 0x1c

section .text
    global _main
_main:
    push ebp
    mov ebp, esp
    sub esp, 1ch

    ; 获取 kernel32.dll 基址
    mov eax, [fs:30h]               ; eax = TEB->PEB
    mov eax, [eax+0ch]              ; eax = PEB->Ldr
    mov eax, [eax+14h]              ; eax = PEB_LDR_DATA->InMemoryOrderModuleList.Flink (当前程序)
    mov eax, [eax]                  ; eax = &_LDR_DATA_TABLE_ENTRY.InMemoryOrderModuleList.Flink (现在是 ntdll.dll)
    mov eax, [eax]                  ; eax = &_LDR_DATA_TABLE_ENTRY.InMemoryOrderModuleList.Flink (现在是 kernel32.dll)
    mov eax, [eax-8h+18h]           ; eax = &_LDR_DATA_TABLE_ENTRY.DllBase (kernel32.dll 基址)

    mov ebx, eax                    ; ebx -> kernel32.dll 基址
    mov [ebp-kernel32_base], eax    ; kernel32_base -> kernel32.dll 基址

    mov eax, [ebx+3ch]
    add eax, ebx                    ; eax -> kernel32.dll 的 pe 文件头

    mov eax, [eax+78h]              ; eax -> ExportDirectory.VirtualAddress
    add eax, ebx                    ; eax -> Export Directory Table

    xor eax, eax
    add esp, 1ch
    pop ebp
    retn
```

接着从 `xor eax,eax` 之前继续。

### 2.3 分析 Export Directory Table

先给出定义。

| Offset | Size | Field                    | Description                                                  |
| :----- | :--- | :----------------------- | :----------------------------------------------------------- |
| 0      | 4    | Export Flags             | Reserved, must be 0.                                         |
| 4      | 4    | Time/Date Stamp          | The time and date that the export data was created.          |
| 8      | 2    | Major Version            | The major version number. The major and minor version numbers can be set by the user. |
| 10     | 2    | Minor Version            | The minor version number.                                    |
| 12     | 4    | Name RVA                 | The address of the ASCII string that contains the name of the DLL. This address is relative to the image base. |
| 16     | 4    | Ordinal Base             | The starting ordinal number for exports in this image. This field specifies the starting ordinal number for the export address table. It is usually set to 1. |
| 20     | 4    | Address Table Entries    | The number of entries in the export address table.           |
| 24     | 4    | Number of Name Pointers  | The number of entries in the name pointer table. This is also the number of entries in the ordinal table. |
| 28     | 4    | Export Address Table RVA | The address of the export address table, relative to the image base. |
| 32     | 4    | Name Pointer RVA         | The address of the export name pointer table, relative to the image base. The table size is given by the Number of Name Pointers field. |
| 36     | 4    | Ordinal Table RVA        | The address of the ordinal table, relative to the image base. |

注意 offset 是 10 进制，之后编写的代码里会用 16 进制。

我们把这个结构里，我们关注的字段保存到栈上。

```asm
    mov ecx, eax                                        ; 暂存导出表结构基址用来运算
    mov [ebp-address_of_export_directory_table], eax    ; 保存导出表结构基址到栈变量
    mov eax, [eax+1ch]
    add eax, ebx
    mov [ebp-address_of_func_address_table], eax        ; 保存导出函数表地址到栈变量
    mov eax, ecx
    mov eax, [eax+24h]
    add eax, ebx
    mov [ebp-address_of_ordinal_table], eax             ; 保存ordinal表地址到栈变量
    mov eax, ecx
    mov eax, [eax+18h]
    mov [ebp-numberof_export_entries], eax              ; 保存导出表(name)数量到栈变量
    mov eax, ecx
    mov eax, [eax+20h]                                  ; eax=第一个函数名称的 RVA
    mov [ebp-address_of_name_table], eax                ; 保存导出函数的名称表到栈变量
    mov eax, ecx
    mov eax, [eax+10h]
    mov [ebp-ordinal_base], eax                         ; 保存 ordinal base 用于计算导出函数的地址
```

应该不难理解。

接下来要从这个结构里找出 `WinExec` 函数的地址。

### 2.4 导出表和函数地址

一些前置知识。

导出函数的地址表是用 Ordinal 做索引的，所以必须先取得 Ordinal 才能正确取得地址。

> The export address table contains the address of exported entry points and exported data and absolutes. An ordinal number is used as an index into the export address table.

注意从 Ordinal Base 取出的值是 **unbiased indexes**，从 Ordinal Table 里取出的 Ordinal 值并不需要减去 Ordinal Base 。但是 DUMPBIN 之类的工具似乎会给出加上了 Ordinal Base 的 Ordinal 值，也就是微软文档中说的 Biased Ordinal 。

这份文档曾经是错误的，[见爆栈的这个问题](https://stackoverflow.com/questions/39996742/how-can-kernel32-dll-export-an-ordinal-of-0-when-its-ordinalbase-field-is-s)。要是看了什么不知道从哪儿复制粘贴来的博客可能会有误解，但现在的文档里是明确说了是 **unbiased indexes** 。取得 Ordinal 之后直接当下标去访问就行了。

> The export ordinal table is an array of **16-bit unbiased indexes** into the export address table. Ordinals are biased by the Ordinal Base field of the export directory table. In other words, the ordinal base must be subtracted from the ordinals to obtain true indexes into the export address table.

文档也明确指出，你可以把名称表和ordinal表当成一个表，下标是共通的。也就是名称表的第1个元素对应ordinal表的第一个元素，以此类推。

> The export name pointer table and the export ordinal table form two parallel arrays that are separated to allow natural field alignment. These two tables, in effect, operate as one table, in which the Export Name Pointer column points to a public (exported) name and the Export Ordinal column gives the corresponding ordinal for that public name. A member of the export name pointer table and a member of the export ordinal table are associated by having the same position (index) in their respective arrays.

现在我们可以开始处理这几个表了。

### 2.5 遍历名称表

字符串常量要记得先定义好，之后用。

```asm
section .data
    str_winexec:
	    db 'WinExec', 0
    str_calcexe:
	    db 'calc.exe', 0
```

首先从名称表里找出 `WinExec` 这个字符串。之后会拿 `eax` 保存下标，`ecx` 用于 `repe cmpsb` 指令，所以这两个字段我们先清空。

```asm
    xor eax, eax
    xor ecx, ecx
```

接着写一个循环。

```asm
.findWinExecLocation:
    mov esi, str_winexec                    ; 准备比较，esi=常量字符串
    mov edi, [ebp-address_of_name_table]    ; 准备比较，edi=名称表首元素，注意名称表是一个指针数组，每个元素都是 DWORD RVA
    cld                                     ; 清除 df 标志位

    mov ecx, eax                            ; 暂存下 eax，接下来 eax 要算下标
    shl eax, 2h                             ; 左移 2 位，等于 eax *= 4
    add edi, eax                            ; 啰嗦这么多就是为了 edi = edi + eax * 4
    mov eax, ecx                            ; 恢复 eax 的值
    
    mov edi, [ebx + edi]                    ; edi = *(基址+名称表RVA[下标])，注意此时拿到的还是一个 RVA ，指向导出函数名字符串
    add edi, ebx                            ; 将 RVA 加上基址，得到完整的地址
    mov cx, 8                               ; repe cmpsb 使用 cx 寄存器来计数，WinExec 长度是 7，加上 NUL 就是 8 个字符
    repe cmpsb                              ; 字符串比较
    
    jz .found                               ; 如果 repe cmpsb 得到的结果是相同，那么当前下标 eax 就是 WinExec 了，跳转出循环
    inc eax                                 ; 否则下标自增
    cmp eax, [ebp-numberof_export_entries]  ; 如果当前下标还不等于导出总数
    jne .findWinExecLocation                ; 继续循环
    
.found:
```

最复杂的部分就是算偏移，在 C 中一个下标运算又或者指针解引用的事情在汇编里就很蛋疼。

### 2.6 取 Ordinal 和函数地址

得到正确下标后就可以取 Ordinal 了。先把 ordinal 表的地址和 函数地址表的地址放进寄存器。

```asm
    mov ecx, [ebp-address_of_ordinal_table]
    mov edx, [ebp-address_of_func_address_table]
```

然后用 eax 做下标，取 ordinal 值。

```asm
    mov ax, [ecx+eax*2]                                 ; ax(ordinal) = ((WORD*)ordinal_table)[eax]
```

再拿 Ordinal 值做下标，取函数地址。

```asm
    mov eax,[edx+eax*4]                                 ; eax = ((DWORD*)address_table)[eax]
```

最后把函数地址（RVA）加上基址。

```asm
    add eax, ebx                                        ; eax=WinExec 函数的地址
```

得到 `WinExec` 函数在内存中的地址。

### 2.7 调用 WinExec 函数

Windows API 都是 *stdcall* 调用约定，我们不用管清栈，直接压参数就好。

```asm
    push 10                                             ; SW_SHOWDEFAULT
    push str_calcexe                                    ; 字符串 calc.exe
    call eax                                            ; __stdcall WinExec
```

到这里，应该就成功调用了 `WinExec` 函数了。

### 2.8 清理和退出

写完了主要功能，接下来就要给自己擦屁股了，平栈。

```asm
    add esp, 1ch
    pop ebp
    xor eax, eax
    retn
```

收工！

### 2.9 完整代码

```asm
%define kernel32_base 0x04
%define numberof_export_entries 0x08
%define address_of_ordinal_table 0x0c
%define address_of_func_address_table 0x10
%define address_of_export_directory_table 0x14
%define address_of_name_table 0x18
%define ordinal_base 0x1c

section .text
    global _main
_main:
    push ebp
    mov ebp, esp
    sub esp, 1ch

    ; 获取 kernel32.dll 基址
    mov eax, [fs:30h]               ; eax = TEB->PEB
    mov eax, [eax+0ch]              ; eax = PEB->Ldr
    mov eax, [eax+14h]              ; eax = PEB_LDR_DATA->InMemoryOrderModuleList.Flink (当前程序)
    mov eax, [eax]                  ; eax = &_LDR_DATA_TABLE_ENTRY.InMemoryOrderModuleList.Flink (现在是 ntdll.dll)
    mov eax, [eax]                  ; eax = &_LDR_DATA_TABLE_ENTRY.InMemoryOrderModuleList.Flink (现在是 kernel32.dll)
    mov eax, [eax-8h+18h]           ; eax = &_LDR_DATA_TABLE_ENTRY.DllBase (kernel32.dll 基址)

    mov ebx, eax                    ; ebx -> kernel32.dll 基址
    mov [ebp-kernel32_base], eax    ; kernel32_base -> kernel32.dll 基址

    mov eax, [ebx+3ch]
    add eax, ebx                    ; eax -> kernel32.dll 的 pe 文件头

    mov eax, [eax+78h]              ; eax -> ExportDirectory.VirtualAddress
    add eax, ebx                    ; eax -> Export Directory Table

    mov ecx, eax                                        ; 暂存导出表结构基址用来运算
    mov [ebp-address_of_export_directory_table], eax    ; 保存导出表结构基址到栈变量
    mov eax, [eax+1ch]
    add eax, ebx
    mov [ebp-address_of_func_address_table], eax        ; 保存导出函数表地址到栈变量
    mov eax, ecx
    mov eax, [eax+24h]
    add eax, ebx
    mov [ebp-address_of_ordinal_table], eax             ; 保存ordinal表地址到栈变量
    mov eax, ecx
    mov eax, [eax+18h]
    mov [ebp-numberof_export_entries], eax              ; 保存导出表(name)数量到栈变量
    mov eax, ecx
    mov eax, [eax+20h]                                  ; eax=第一个函数名称的 RVA
    mov [ebp-address_of_name_table], eax                ; 保存导出函数的名称表到栈变量
    mov eax, ecx
    mov eax, [eax+10h]
    mov [ebp-ordinal_base], eax                         ; 保存 ordinal base 用于计算导出函数的地址

    xor eax,eax
    xor ecx,ecx
.findWinExecLocation:
    mov esi, str_winexec                    ; 准备比较，esi=常量字符串
    mov edi, [ebp-address_of_name_table]    ; 准备比较，edi=名称表首元素
    cld                                     ; 清除 df 标志位

    mov ecx, eax                            ; 暂存下 eax，接下来 eax 要算下标
    shl eax, 2h                             ; 左移 2 位，等于 eax *= 4
    add edi, eax                            ; 啰嗦这么多就是为了 edi = edi + eax * 4
    mov eax, ecx                            ; 恢复 eax 的值

    mov edi, [ebx + edi]                    ; edi = *(基址+名称表RVA[下标])，注意此时拿到的还是一个 RVA ，指向导出函数名字符串
    add edi, ebx                            ; 将 RVA 加上基址，得到完整的地址
    mov cx, 8                               ; repe cmpsb 使用 cx 寄存器来计数，WinExec 长度是 7，加上 NUL 就是 8 个字符
    repe cmpsb                              ; 字符串比较

    jz .found                               ; 如果 repe cmpsb 得到的结果是相同，那么当前下标 eax 就是 WinExec 了，跳转出循环
    inc eax                                 ; 否则下标自增
    cmp eax, [ebp-numberof_export_entries]  ; 如果当前下标还不等于导出总数
    jne .findWinExecLocation                ; 继续循环

.found:
    mov ecx, [ebp-address_of_ordinal_table]
    mov edx, [ebp-address_of_func_address_table]

    mov ax, [ecx+eax*2]                                 ; ax(ordinal) = ((WORD*)ordinal_table)[eax]
    mov eax,[edx+eax*4]                                 ; eax = ((DWORD*)address_table)[eax]
    add eax, ebx                                        ; eax=WinExec 函数的地址

    push 10                                             ; SW_SHOWDEFAULT
    push str_calcexe                                    ; 字符串 calc.exe
    call eax                                            ; __stdcall WinExec

    add esp, 1ch
    pop ebp
    xor eax, eax
    retn

section .data
    str_winexec:
        db 'WinExec', 0
    str_calcexe:
        db 'calc.exe', 0
```



## 0x03 验证

验证方法很简单，我们编译之，运行，然后就好啦！

![image-20211014161140486](image/关于在内存里找kernel32这件事/image-20211014161140486.png)

`WinExec` 的返回值在 eax 里，微软的文档说返回值大于 31 就是 OJBK，0x21 是10进制的33，所以完全 OJBK 。

## 总结

这是写 shellcode 的技术吧，东一榔头西一棒子就是我了。话说 shellcode 的具体定义是啥来着？我只剩菜了.jpg

最终体会就是写过汇编才知道 C 真的是很高级的语言了（

真要算地址算偏移一算一整天，365天对着16进制数做加减乘除那真就是折磨。

Windows 未公开的数据结构也不知道网上的大佬都是怎么研究出来的，毕竟理论上来说搞这个没有任何价值，在逆向研究出结果之前谁也不知道这些东西能带来什么价值，甚至你搞完了也不知道有什么价值，直到有一天被正好有需要的人发现（大黑阔：现成的洞，好耶）。

嗯，这个想法就让人比较兴奋，顿时感觉自己闲出屁摸鱼也是在为社会创造价值了呢~

另外关于如何用 C 写 shellcode，其实我想了下，也许可以让编译器把汇编吐出来，然后从里面拿咱需要的代码？不过这也不知道怎么编译器吐出能让 nasm 接受的汇编。或者有啥比较业界通行的语法标准？只知道有 AT&T 和 Intel 两种风格，但非要说的话 nasm 和 masm 都有些不兼容，尽管都是 Intel 风格（大概）。或者就是让编译器吐个 obj 文件出来，然后解析这个 obj ，提取里面的二进制代码就好。

好了瞎bb完毕。收工啦。