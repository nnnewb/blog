---
title: 在C++中嵌入Python解释器
categories:
  - c++
tags:
  - c++
  - python
  - 酷Q
date: 2020-2-7 21:59:00
---

先不说废话，项目地址：https://github.com/nnnewb/CQPy 。欢迎给个 Star 什么的。

## 背景

想给最近在玩的酷 Q 写个插件，发现没有合适的直接使用 Python 的解决方案。

Richard Chien 提供了一个比较通用的插件，`CQHttp`。`CQHttp`本体是用 C++ 编写的插件，将酷 Q 的回调包装成 HTTP 请求转发至指定的地址，支持`http`和`websocket`两种协议。

不过由于个人想折腾折腾的想法，打算试试把 Python 解释器直接嵌入到 C++ 里得了。

<!-- more -->

整个思路如下。

```mermaid
graph LR;
    CQP[酷Q] --事件回调--> dll[插件DLL];
    dll --事件回调--> python[Python脚本];
    python --调用API--> dll;
    dll --调用API--> CQP;
```

## 依赖

为了简化操作 Python 接口，我没有使用 Python 自带的 C API，而是`pybind11`，使用`vcpkg`管理依赖。

安装命令：

```batch
vcpkg install pybind11:x86-windows
```

## 0x1 编译 DLL

我使用 CMake 作为编译系统，因此可以很简单地写一个编译出 DLL 的 `CMakeLists.txt`

```cmake
cmake_minimum_required(VERSION 3.15)
project(top.weak-ptr.cqpy LANGUAGES CXX VERSION 0.1.0)

include_directories(src)
aux_source_directory(src SOURCES)
set(CMAKE_CXX_STANDARD 17)

# 引入 pybind11
find_package(pybind11 CONFIG REQUIRED)

# 添加 target
set(OUT_NAME "app")
add_library(${OUT_NAME} SHARED ${SOURCES})
set_target_properties(${OUT_NAME} PROPERTIES LINKER_LANGUAGE CXX)
target_link_libraries(${OUT_NAME} PRIVATE pybind11::embed)
```

源代码使用 MSVC 和 MinGW 编译，另外再处理下源码编码的问题和宏。

主要涉及的几个问题：

1. MSVC 编译时通过`/utf-8`编译参数指定源码文件的编码。
2. MSVC 编译`pybind11`时需要指定 `-DNOMINMAX`，这是`pybind11`要求的。
3. 因为使用 VCPKG 管理依赖，MSVC 编译时还需要设置链接属性。
4. MinGW 编译时，指定 `-static` 避免依赖 `libgcc` 之类的 dll，最终编译结果只依赖于 `libpython3.7.dll`。
5. MinGW 编译时，指定 `-Wl,--kill-at,--enable-stdcall-fixup`，来确保导出的 DLL API 名字没有下划线开头和`@<参数大小>`的后缀。

```cmake
# 添加编译参数
add_compile_definitions(APP_ID="${PROJECT_NAME}")
add_definitions(-DAPP_ID="top.weak-ptr.cqpy")
if (MSVC)
    add_compile_options(/utf-8)
    add_definitions(-DNOMINMAX)

    # 设置静态链接
    set(VCPKG_CRT_LINKAGE STATIC)
    set(VCPKG_LIBRARY_LINKAGE STATIC)
else ()
    add_link_options(-static -Wl,--kill-at,--enable-stdcall-fixup)
endif (MSVC)
```

最后的构建命令：

```batch
mkdir build
cd build
cmake .. \
    "-GVisual Studio 16 2019" \
    -AWin32 \
    -DCMAKE_TOOLCHAIN_FILE=/path/to/your/vcpkg/scripts/buildsystems/vcpkg.cmake \
cmake --build .
cmake install
```

MinGW 对应改下 Generator，去掉`-AWin32`和后面的`-DCMAKE_TOOLCHAIN_FILE=/path/to/your/vcpkg/scripts/buildsystems/vcpkg.cmake`即可。

## 0x2 MSVC 编译导出 DLL 的问题

参考 MSDN 的文档，使用下面的方式无法正确导出 DLL 接口。

```c++
extern "C" __declspec(dllexport) int __stdcall test() {}
```

最终采用的是`__pragma`的方式指定导出名，如下。

```c++
#define DLL_EXPORT extern "C" __declspec(dllexport)

#define CQ_EXPORT(ReturnType, FuncName, ParamsSize, ...)                       \
  __pragma(                                                                    \
      comment(linker, "/EXPORT:" #FuncName "=_" #FuncName "@" #ParamsSize))    \
      DLL_EXPORT ReturnType __stdcall FuncName(__VA_ARGS__)
```

注意`__pragma`只能在 MSVC 中使用，所以要加上条件判断。

```c++
#define DLL_EXPORT extern "C" __declspec(dllexport)

#if defined(_MSC_VER)
#define CQ_EXPORT(ReturnType, FuncName, ParamsSize, ...)                       \
  __pragma(                                                                    \
      comment(linker, "/EXPORT:" #FuncName "=_" #FuncName "@" #ParamsSize))    \
      DLL_EXPORT ReturnType __stdcall FuncName(__VA_ARGS__)
#else
#define CQ_EXPORT(ReturnType, FuncName, ParamsSize, ...)                       \
  DLL_EXPORT ReturnType __stdcall FuncName(__VA_ARGS__)
#endif
```

理论上也能用`.def`文件来定义导出表，可以自行尝试下。

## 0x3 导入 CQP.dll 的 API 的问题

首先要知道`CQP.dll`也会加载到`CQP.exe`中，插件也会加载到`CQP.exe`中，所以我们需要的就是使用 Windows API 获取到`CQP.dll`的 Handle 再进行操作。

大致代码如下。

```c++
const auto dll = GetModuleHandleW(L"CQP.dll");
const auto CQ_addLog = reinterpret_cast<int32_t (__stdcall *)(int32_t,int32_t,const char*,const char*)>(GetProcAddress(dll, "CQ_addLog"));
```

通过两个 API 调用即可获得需要的函数指针了。

## 0x4 嵌入 Python 解释器

到了这一步已经非常简单了，`pybind11`提供了高度封装的 C++ API。可以直接参考[这个文档](https://pybind11.readthedocs.io/en/stable/advanced/embedding.html)。

再给个简单的例子代码：

```c++
template <typename... Args>
inline int32_t py_callback(const std::string &py_func, Args... args) {
  auto guard = std::lock_guard(lock);

  try {
    auto m = py::module::import("cqpy._callback");
    return m.attr(py_func.c_str())(args...).template cast<int32_t>();
  } catch (const py::error_already_set &e) {
    logging::error(e.what()); // 记录 python 错误到日志
    return -1;
  }
}

// 启用插件
CQ_EXPORT(int32_t, cq_event_enable, 0) {
  py::initialize_interpreter();
  // 设置 AUTH_CODE，但是暂时还不能使用酷Q的API
  auto _embed = py::module::import("_embed");
  _embed.attr("AUTH_CODE") = AUTH_CODE;
  // 初始化 Python 解释器环境，把数据目录加入 python path
  auto raw_app_dir = std::string(CQ_getAppDirectory(AUTH_CODE));
  auto app_dir = py::bytes(raw_app_dir).attr("decode")("gb18030").cast<py::str>();
  auto sys = py::module::import("sys");
  sys.attr("path").attr("append")(app_dir);
  // 初始化完成
  logging::info("Python interpreter initialized.");
  return py_callback("on_enable");
}
```

需要注意的是，虽然在前面通过相关参数指定了静态链接，但实际`Python3.7.dll`还是动态链接上去的。

所以分发这样编译出来的 dll，依然需要用户先安装一个 `Python3.7`，或者把 `Python3.7.dll` 也一起分发出去。

如果要完全的静态链接，可能要自行编译 Python 源代码。实在太麻烦，就懒得弄了。

## 0x5 踩的坑

通过 Python 调用 C++ 端提供的 API 时，特别注意参数一定要一一对应，特别是数据类型，一旦不匹配或传入数据有误（例如 None），可能造成 C++ 端内存异常，需要挂调试器才能发现原因，非常麻烦。

`sys`是`builtin`的库，和`os`不同，如果分发的用户没有安装 Python，只有一个 `Python3.7.dll`的话，很多 Python 自带的库是用不了的。例如说`json`、`logging`、甚至`os`。这个应该算是常识，但最好一开始就意识到：你的用户还是要装一个 Python 才行。

关于 VirtualEnv 支持，建议直接参考[PEP 405](https://www.python.org/dev/peps/pep-0405/)。不多赘述。比较简单的处理就是把`VENV\Lib\site-packages`加入到`sys.path`里。

能不能把所有 Python 代码和 dll 都打包进 dll 里？大致原理就是丢进`rc`里，但实际很麻烦，看`py2exe`迄今为止还有一大堆坑就知道有多麻烦了。
