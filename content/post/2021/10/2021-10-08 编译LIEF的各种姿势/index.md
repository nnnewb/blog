---
title: 编译LIEF的各种姿势
slug: how-to-compile-lief-on-windows
date: 2021-10-08 16:25:00
categories:
- c++
tags:
- c++
- LIEF
---

## 前言

惯例得有个前言。

LIEF是一个二进制文件分析和操作库，官方推荐的是 Python 版本，确实更好用，就是类型的问题有点多，而且没附送 `.pyi` 导致不大好写。而C++版本就没这问题，C++版本有自己的问题=，=

一个是官方提供下载的SDK是静态链接的，用到SDK的程序必须指定 `/MT` 不然编译器就会抱怨运行库不匹配。虽然看issue里已经有人解决了（`-DLIEF_USE_CRT_{DEBUG,RELEASE}=MD/MT`），但CI还是老样子，反正直接下载的SDK用起来就蛋疼，vcpkg 全都是 `/MD` 链接的，没法配合用。

更别提 MinGW 了，就没官方的SDK。

以上就是问题，解决问题的最简单办法就是自己编译了。

## 0x01 Visual C++ 工具链 msbuild

代码下载下来之后，用 CMake 去编译。下面的命令都是 Powershell 下的，注意折行用的是反引号 backquote，就是波浪号那个键，和 bash 用 反斜杠不一样。直接复制到命令行是跑不起来的。

```powershell
cmake .. 
	-G "Visual Studio 2019" # Generator，你的工具链，可以用 cmake --help 来看看有哪些可用的
	-A Win32 # 选择 Visual C++ 工具链的情况下可以用 -A Win32 选择编译32位代码，或者 Win64
	-DCMAKE_BUILD_TYPE=Debug # 常用的 Debug/Release/RelWithDebInfo
	-DLIEF_PYTHON_API=off # 不编译 Python 模块，这样就不用装 Python 了
	-DLIEF_USE_CRT_DEBUG=MD # 使用 /MD 链接 msvcrt.dll 而不是 libcmt
```

这儿有个坑，用 Visual Studio 这个 Generator 的时候，虽然指定了 `CMAKE_BUILD_TYPE`，但实际没什么卵用，还得在编译的时候给参数 `--config Debug` 才会真的按 Debug 编译。

然后是编译命令：

```powershell
cmake --build . --config Debug --target LIB_LIEF
```

默认用微软的 msbuild 会花很长时间去编译，不嫌麻烦的话可以用 Ninja。

编译完还不能用，还得先“安装”到一个目录里。

```powershell
cmake --install . --config Debug --prefix LIEF-msvc-debug
```

这样就会把必要的文件给复制到 `LIEF-msvc-debug` 这个文件夹里了，参考 LIEF 官方的集成文档，把 `LIEF_DIR` 设置成这个文件夹的路径就可以用啦。

## 0x02 Visual C++ 工具链 ninja

使用 CMake + Ninja 的情况下没法用 `-A` 去控制编译32位还是64位了，你得先装好 Visual C++ 构建工具，然后打开开发者命令提示符。

![image-20211008160449880](image/how-to-compile-lief-on-windows/image-20211008160449880.png)

比如想编译32位的就选 `x86 native tool command prompt` ，在这个命令提示符里用 cmake 构建。

```powershell
cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Debug -DLIEF_PYTHON_API=off -DLIEF_USE_CRT_DEBUG=MD
cmake --build . --target LIB_LIEF
cmake --install . --prefix LIEF-msvc-debug
```

其他和直接用 msvc 没啥区别。

## 0x03 MinGW 工具链 makefile

MinGW 工具链其实和 msvc 差不太大。先装 MinGW，推荐 msys2，msys2装好后跑命令 `pacman -Sy mingw-w64-i686-toolchain` 就能装上32位的编译工具链了，包括了 `gcc`、`g++`、`mingw32-make` 这些必要的程序。

完事后把 `MinGW` 工具链加到 `PATH` 里。一般来说，假如你把 msys2 装到 `C:\msys64` 下的话，那要加的路径就是 `C:\msys64\mingw32\bin`，自己看看要用的 gcc 放在哪儿呗。

另外 `LIEF_USE_CRT_DEBUG` 这变量也用不到了，`MD`还是`MT` 这是专供 MSVC 的选择题，MinGW 不管这个。

接着就可以用 CMake 了。

```powershell
cmake .. -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Debug -DLIEF_PYTHON_API=off '-DCMAKE_C_FLAGS:STRING="-m32"' '-DCMAKE_CXX_FLAGS:STRING="-m32"'
cmake --build . --target LIB_LIEF
cmake --install . --prefix LIEF-mingw32-debug
```

不用担心 CMake 选错工具链，用 `MinGW Makefiles` 的情况下会优先考虑 GCC 的。不过还有个老问题：怎么选32位还是64位。答案是设置下 `C_FLAGS` 和 `CXX_FLAGS` 这两个特殊变量，让编译器加上 `-m32` 这个参数，编译出来的就是32位代码了。

## 0x04 MinGW 工具链 Ninja

和 `MinGW Makefiles` 差不太多，但是 `Ninja` 没那么聪明，不知道要用什么编译器，得手动指定。

```powershell
cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Debug -DLIEF_PYTHON_API=off -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ '-DCMAKE_C_FLAGS:STRING="-m32"' '-DCMAKE_CXX_FLAGS:STRING="-m32"'
cmake --build . --target LIB_LIEF
cmake --install . --prefix LIEF-mingw32-debug
```

配置阶段多出来两个参数，`-DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++`，目的就是告诉 CMake 放机灵点，用 `gcc/g++` 编译器，别瞎整。

## 总结

也就这么回事吧。

