---
title: 加壳原理02 - 简单加壳机
slug: learning-packer-02
date: 2021-09-28 16:57:00
image: cover.jpg
categories:
- 逆向
tags:
- 逆向
- 汇编
- Windows
- security
- binary-analysis
---

## 前言

对 Windows 程序的加载和运行过程有了基本了解后，手动加载并运行一个PE文件并不成问题。加壳仅仅是在这上面更进一步：把加载程序和被加载的程序合并成一个文件。

这么说可能有点太简单化，大部分的工作其实就在这儿：如何处理被加载的程序？压缩？加密？混淆？加载器（或者叫壳程序）如何反调试？

这里先写一个简单的加壳机，仅仅是把被加载的PE文件作为一个 Section，添加到壳程序里，让壳程序直接从这个 Section 加载并运行。其他花里胡哨的操作都先不整，仅作为证明工作原理的案例。

## 0x01 壳程序

### 1.1 思路

和加载一个PE文件不同，既然被加载的程序就在 Section 里，那需要做的只有定位到 Section，然后把 Section 内容当读取进内存的 PE 文件内容处理就好了。

壳程序应该尽量保持轻量，不在原始程序上添加太多东西（加完壳大小翻一倍还多了一堆DLL依赖那谁受得了啊），所以很多标准C库的函数也不能用了，像是`memcpy`、`strcmp` 都要自己简单实现一个。

### 1.2  壳实现

绝大部分内容和之前文章中的 `load_PE` 一致，入口点修改为 `_start`，需要注意。

```c
#include <Windows.h>
#include <winnt.h>

void *load_PE(char *PE_data);
void fix_iat(char *p_image_base, IMAGE_NT_HEADERS *p_NT_headers);
void fix_base_reloc(char *p_image_base, IMAGE_NT_HEADERS *p_NT_headers);
int mystrcmp(const char *str1, const char *str2);
void mymemcpy(char *dest, const char *src, size_t length);

int _start(void) {
  char *unpacker_VA = (char *)GetModuleHandleA(NULL);

  IMAGE_DOS_HEADER *p_DOS_header = (IMAGE_DOS_HEADER *)unpacker_VA;
  IMAGE_NT_HEADERS *p_NT_headers = (IMAGE_NT_HEADERS *)(((char *)unpacker_VA) + p_DOS_header->e_lfanew);
  IMAGE_SECTION_HEADER *sections = (IMAGE_SECTION_HEADER *)(p_NT_headers + 1);

  char *packed = NULL;
  char packed_section_name[] = ".packed";

  for (int i = 0; i < p_NT_headers->FileHeader.NumberOfSections; i++) {
    if (mystrcmp(sections[i].Name, packed_section_name) == 0) {
      packed = unpacker_VA + sections[i].VirtualAddress;
      break;
    }
  }

  if (packed != NULL) {
    void (*entrypoint)(void) = (void (*)(void))load_PE(packed);
    entrypoint();
  }

  return 0;
}

void *load_PE(char *PE_data) {
  IMAGE_DOS_HEADER *p_DOS_header = (IMAGE_DOS_HEADER *)PE_data;
  IMAGE_NT_HEADERS *p_NT_headers = (IMAGE_NT_HEADERS *)(PE_data + p_DOS_header->e_lfanew);

  // extract information from PE header
  DWORD size_of_image = p_NT_headers->OptionalHeader.SizeOfImage;
  DWORD entry_point_RVA = p_NT_headers->OptionalHeader.AddressOfEntryPoint;
  DWORD size_of_headers = p_NT_headers->OptionalHeader.SizeOfHeaders;

  // allocate memory
  // https://docs.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualalloc
  char *p_image_base = (char *)VirtualAlloc(NULL, size_of_image, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
  if (p_image_base == NULL) {
    return NULL;
  }

  // copy PE headers in memory
  mymemcpy(p_image_base, PE_data, size_of_headers);

  // Section headers starts right after the IMAGE_NT_HEADERS struct, so we do some pointer arithmetic-fu here.
  IMAGE_SECTION_HEADER *sections = (IMAGE_SECTION_HEADER *)(p_NT_headers + 1);

  for (int i = 0; i < p_NT_headers->FileHeader.NumberOfSections; i++) {
    // calculate the VA we need to copy the content, from the RVA
    // section[i].VirtualAddress is a RVA, mind it
    char *dest = p_image_base + sections[i].VirtualAddress;

    // check if there is Raw data to copy
    if (sections[i].SizeOfRawData > 0) {
      // We copy SizeOfRaw data bytes, from the offset PointerToRawData in the file
      mymemcpy(dest, PE_data + sections[i].PointerToRawData, sections[i].SizeOfRawData);
    } else {
      for (size_t i = 0; i < sections[i].Misc.VirtualSize; i++) {
        dest[i] = 0;
      }
    }
  }

  fix_iat(p_image_base, p_NT_headers);
  fix_base_reloc(p_image_base, p_NT_headers);

  // Set permission for the PE header to read only
  DWORD oldProtect;
  VirtualProtect(p_image_base, p_NT_headers->OptionalHeader.SizeOfHeaders, PAGE_READONLY, &oldProtect);

  for (int i = 0; i < p_NT_headers->FileHeader.NumberOfSections; ++i) {
    char *dest = p_image_base + sections[i].VirtualAddress;
    DWORD s_perm = sections[i].Characteristics;
    DWORD v_perm = 0; // flags are not the same between virtal protect and the section header
    if (s_perm & IMAGE_SCN_MEM_EXECUTE) {
      v_perm = (s_perm & IMAGE_SCN_MEM_WRITE) ? PAGE_EXECUTE_READWRITE : PAGE_EXECUTE_READ;
    } else {
      v_perm = (s_perm & IMAGE_SCN_MEM_WRITE) ? PAGE_READWRITE : PAGE_READONLY;
    }
    VirtualProtect(dest, sections[i].Misc.VirtualSize, v_perm, &oldProtect);
  }

  return (void *)(p_image_base + entry_point_RVA);
}

void fix_iat(char *p_image_base, IMAGE_NT_HEADERS *p_NT_headers) {
  IMAGE_DATA_DIRECTORY *data_directory = p_NT_headers->OptionalHeader.DataDirectory;

  // load the address of the import descriptors array
  IMAGE_IMPORT_DESCRIPTOR *import_descriptors =
      (IMAGE_IMPORT_DESCRIPTOR *)(p_image_base + data_directory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress);

  // this array is null terminated
  for (int i = 0; import_descriptors[i].OriginalFirstThunk != 0; ++i) {
    // Get the name of the dll, and import it
    char *module_name = p_image_base + import_descriptors[i].Name;
    HMODULE import_module = LoadLibraryA(module_name);
    if (import_module == NULL) {
      // panic!
      ExitProcess(255);
    }

    // the lookup table points to function names or ordinals => it is the IDT
    IMAGE_THUNK_DATA *lookup_table = (IMAGE_THUNK_DATA *)(p_image_base + import_descriptors[i].OriginalFirstThunk);

    // the address table is a copy of the lookup table at first
    // but we put the addresses of the loaded function inside => that's the IAT
    IMAGE_THUNK_DATA *address_table = (IMAGE_THUNK_DATA *)(p_image_base + import_descriptors[i].FirstThunk);

    // null terminated array, again
    for (int i = 0; lookup_table[i].u1.AddressOfData != 0; ++i) {
      void *function_handle = NULL;

      // Check the lookup table for the adresse of the function name to import
      DWORD lookup_addr = lookup_table[i].u1.AddressOfData;

      if ((lookup_addr & IMAGE_ORDINAL_FLAG) == 0) { // if first bit is not 1
        // import by name : get the IMAGE_IMPORT_BY_NAME struct
        IMAGE_IMPORT_BY_NAME *image_import = (IMAGE_IMPORT_BY_NAME *)(p_image_base + lookup_addr);
        // this struct points to the ASCII function name
        char *funct_name = (char *)&(image_import->Name);
        // get that function address from it's module and name
        function_handle = (void *)GetProcAddress(import_module, funct_name);
      } else {
        // import by ordinal, directly
        function_handle = (void *)GetProcAddress(import_module, (LPSTR)lookup_addr);
      }

      if (function_handle == NULL) {
        ExitProcess(255);
      }

      // change the IAT, and put the function address inside.
      address_table[i].u1.Function = (DWORD)function_handle;
    }
  }
}

void fix_base_reloc(char *p_image_base, IMAGE_NT_HEADERS *p_NT_headers) {
  IMAGE_DATA_DIRECTORY *data_directory = p_NT_headers->OptionalHeader.DataDirectory;

  // this is how much we shifted the ImageBase
  DWORD delta_VA_reloc = ((DWORD)p_image_base) - p_NT_headers->OptionalHeader.ImageBase;

  // if there is a relocation table, and we actually shitfted the ImageBase
  if (data_directory[IMAGE_DIRECTORY_ENTRY_BASERELOC].VirtualAddress != 0 && delta_VA_reloc != 0) {

    // calculate the relocation table address
    IMAGE_BASE_RELOCATION *p_reloc =
        (IMAGE_BASE_RELOCATION *)(p_image_base + data_directory[IMAGE_DIRECTORY_ENTRY_BASERELOC].VirtualAddress);

    // once again, a null terminated array
    while (p_reloc->VirtualAddress != 0) {

      // how any relocation in this block
      // ie the total size, minus the size of the "header", divided by 2 (those are words, so 2 bytes for each)
      DWORD size = (p_reloc->SizeOfBlock - sizeof(IMAGE_BASE_RELOCATION)) / 2;
      // the first relocation element in the block, right after the header (using pointer arithmetic again)
      WORD *fixups = (WORD *)(p_reloc + 1);
      for (size_t i = 0; i < size; ++i) {
        // type is the first 4 bits of the relocation word
        int type = fixups[i] >> 12;
        // offset is the last 12 bits
        int offset = fixups[i] & 0x0fff;
        // this is the address we are going to change
        DWORD *change_addr = (DWORD *)(p_image_base + p_reloc->VirtualAddress + offset);

        // there is only one type used that needs to make a change
        switch (type) {
        case IMAGE_REL_BASED_HIGHLOW:
          *change_addr += delta_VA_reloc;
          break;
        default:
          break;
        }
      }

      // switch to the next relocation block, based on the size
      p_reloc = (IMAGE_BASE_RELOCATION *)(((DWORD)p_reloc) + p_reloc->SizeOfBlock);
    }
  }
}

int mystrcmp(const char *str1, const char *str2) {
  while (*str1 == *str2 && *str1 != 0) {
    str1++;
    str2++;
  }
  if (*str1 == 0 && *str2 == 0) {
    return 0;
  }
  return -1;
}

void mymemcpy(char *dest, const char *src, size_t length) {
  for (size_t i = 0; i < length; i++) {
    dest[i] = src[i];
  }
}
```

构建参数（CMAKE）

```cmake
add_executable(loader_2 WIN32 loader_2.c)
target_compile_options(loader_2 PRIVATE /GS-)
target_link_options(loader_2 PRIVATE /NODEFAULTLIB /ENTRY:_start)
```

参数`/GS-`是为了避免在`/NODEFAULTLIB`下出现一些缓存区安全检查代码链接错误。参考[文档](https://docs.microsoft.com/en-us/cpp/build/reference/gs-buffer-security-check?view=msvc-160)。

## 0x02 加壳机

相信已经发现了，上文并没有提到怎么把程序嵌入壳程序里。这是因为加壳并不是在壳程序编译时直接把文件嵌进去=，=虽然理论上来说也可以，但这里不讨论了。仅仅看加壳机加壳的场景吧。

### 2.1 加壳机原理

加壳机做的事情包括：

- 在 section table 里添加 section
  - 根据 section table 和 file_alignment 决定如何分配空间
  - 根据 section_alignment 计算 virtual size
  - 根据上一个 section 大小和位置计算 virtual address
  - 填充 pointer_to_raw_data 和 size_of_raw_data
  - 设置合适的 characteristics
- 计算修改 number_of_sections
- 计算修改 size_of_image
- 计算修改 size_of_headers

反正看起来就很麻烦，不过幸好操作 PE 文件的库不少，GitHub 搜一搜就有。这里用 [LIEF](https://github.com/lief-project/LIEF) 这个库，操作蛮简单的。

### 2.2 源码

```cpp
#include <Windows.h>
#include <LIEF/LIEF.hpp>
#include <vector>

std::vector<uint8_t> read_file(const std::string &path) {
  auto h = CreateFile(path.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  DWORD readbyte = 0;
  auto filesize = GetFileSize(h, nullptr);
  auto content = std::vector<uint8_t>();
  content.resize(filesize, 0);
  if (!ReadFile(h, content.data(), filesize, &readbyte, nullptr)) {
    abort();
  }
  if (readbyte != filesize) {
    abort();
  }

  CloseHandle(h);
  return content;
}

int main(int argc, const char *argv[]) {
  if (argc < 3) {
    printf("loader and program path are required");
    return -1;
  }
  auto loader_path = argv[1];
  auto program_path = argv[2];
  auto loader_binary = LIEF::PE::Parser::parse(loader_path);

  // LIEF 帮我们做了偏移计算之类的工作，这里就只用点逻辑，非常得银杏。
  auto program_content = read_file(program_path);
  auto packed_section = LIEF::PE::Section(".packed"); // 新建 section
  packed_section.content(program_content); // 把被加载程序的内容当成 section 内容
  loader_binary->add_section(packed_section, LIEF::PE::PE_SECTION_TYPES::DATA); // 把 section 添加到壳程序里

  // 用 lief 实现把修改后的壳程序写入硬盘
  auto builder = LIEF::PE::Builder::Builder(loader_binary.get());
  builder.build();
  builder.write("packed.exe");

  return 0;
}
```

编译指令（CMAKE）参考 [LIEF 文档](https://lief-project.github.io//doc/latest/installation.html#cmake-integration)。

```cmake
# Custom path to the LIEF install directory
set(LIEF_DIR CACHE PATH ${CMAKE_INSTALL_PREFIX})

# Directory to 'FindLIEF.cmake'
list(APPEND CMAKE_MODULE_PATH ${LIEF_DIR}/share/LIEF/cmake)

# include 'FindLIEF.cmake'
include(FindLIEF)

# Find LIEF
find_package(LIEF REQUIRED COMPONENTS STATIC) # COMPONENTS: <SHARED | STATIC> - Default: STATIC

add_executable(packer packer.cpp)
if(MSVC)
	target_compile_options(packer PRIVATE /FIiso646.h /MT)
	set_property(TARGET packer PROPERTY LINK_FLAGS /NODEFAULTLIB:MSVCRT)
endif()
target_include_directories(packer PRIVATE ${LIEF_INCLUDE_DIRS})
set_property(TARGET packer
			PROPERTY CXX_STANDARD 11
			PROPERTY CXX_STANDARD_REQUIRED ON)
target_link_libraries(packer PRIVATE ${LIEF_LIBRARIES})
```

我要顺便一提，LIEF有python包，但那玩意儿不知道为啥赋值content一直报 not supported，没解决。就干脆拿 c++ 写了。论简单快捷还是要看 python 版本的。

## 结论

加壳程序反而平平无奇，正印证了那句台下功夫。

