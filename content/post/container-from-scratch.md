---
title: 从零实现一个容器
date: 2021-5-31 16:16:52
tags: ["golang","docker"]
categories: ["golang"]
---

## 前言

自从看了`cocker`项目的ppt之后就有点念念不忘的意思了，实现一个docker或docker的类似物看起来并不是做不到的事情。

于是就动手试一试。

## 核心技术

### namespace

命名空间包装全局系统资源，让在命名空间中的进程看起来就像是有自己独立隔离的全局资源一样。命名空间中的全局资源对命名空间中的其他进程都是可见的，但对命名空间外的进程不可见。命名空间用途之一就是实现容器。

>     Linux provides the following namespaces:
>
>     Namespace   Constant          Isolates
>     Cgroup      CLONE_NEWCGROUP   Cgroup root directory
>     IPC         CLONE_NEWIPC      System V IPC, POSIX message queues
>     Network     CLONE_NEWNET      Network devices, stacks, ports, etc.
>     Mount       CLONE_NEWNS       Mount points
>     PID         CLONE_NEWPID      Process IDs
>     User        CLONE_NEWUSER     User and group IDs
>     UTS         CLONE_NEWUTS      Hostname and NIS domain name

几个命名空间的 API

- `clone`
- `setns`
- `unshare`

不得不说 `man 7 namespaces` 对 `namespace` 的解释已经非常到位了。

### chroot

这个 Linux 用户应该还是比较熟悉的，如 Arch Linux 这样的发行版在安装时就有用到。

使用 `man 2 chroot` 查看这个api的文档。

> chroot()  changes  the root directory of the calling process to that specified in path.  This directory will be used for pathnames beginning with /.  The root directory is inherited by all children of the calling process.
>
> Only a privileged process (Linux: one with the CAP_SYS_CHROOT capability in its user namespace) may call chroot().

基本作用是把调用进程的根目录 `/` 切换到指定目录，子进程会继承这个 `/` 位置；调用 API 需要特权。

举例说调完 `chroot("/home/xxx")`，你再用 `ls` 之类的命令看 `/` 下有什么文件，看到的就是 `/home/xxx` 下的内容了。

`man 2 chroot` 还有一些有意思的内容，不做赘述。

### mount

也是 Linux 用户很熟悉的东西。老规矩，`man 2 mount` 看看文档。

> ```c
> #include <sys/mount.h>
>
> int mount(const char *source, const char *target,
>     const char *filesystemtype, unsigned long mountflags,
>     const void *data);
> ```
>
>
>
> mount()  attaches the filesystem specified by source (which is often a pathname referring to a device, but can also be the pathname of a directory or file, or a dummy string) to the location (a directory or file) specified by the pathname in target.

`mount` 会挂载(attaches) `source` 参数指定的文件系统（通常是设备路径，也可以是文件夹、文件的路径或虚拟字符串（如`proc`））到 `target` 指定的位置（目录或文件）。同样需要特权来执行。

`source`/`target` 都不难理解，`filesystemtype`可以从`/proc/filesystems`里读到可用值，或者自己搜一搜；比较重要的就是 `mountflags` 了，可以指定诸如`MS_RDONLY`之类的选项来挂载只读文件系统等等。具体还是自己查手册。

### clone

最后就是系统调用 `clone` 了。还是先 `man 2 clone`。

> ```c
> /* Prototype for the glibc wrapper function */
>
> #define _GNU_SOURCE
> #include <sched.h>
>
> int clone(int (*fn)(void *), void *child_stack,
>           int flags, void *arg, ...
>           /* pid_t *ptid, void *newtls, pid_t *ctid */ );
>
> /* For the prototype of the raw system call, see NOTES */
> ```
>
>  clone() creates a new process, in a manner similar to fork(2).

总体类似于`fork()`，但可以指定一个入口函数，函数结束则子进程退出，也可以共享内存空间，所以行为也可以类似线程。看怎么用。

`flags`依然是关注的重点，`CLONE_NEWUTS`、`CLONE_NEWNS`、`CLONE_NEWPID`这些参数允许将子进程运行在独立的命名空间里。

`man 2 clone` 还提供了一个 C 语言编写的例子可以参考。

```c
#define _GNU_SOURCE
#include <sys/wait.h>
#include <sys/utsname.h>
#include <sched.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define errExit(msg)        \
    do                      \
    {                       \
        perror(msg);        \
        exit(EXIT_FAILURE); \
    } while (0)

static int /* Start function for cloned child */
childFunc(void *arg)
{
    struct utsname uts;

    /* Change hostname in UTS namespace of child */

    if (sethostname(arg, strlen(arg)) == -1)
        errExit("sethostname");

    /* Retrieve and display hostname */

    if (uname(&uts) == -1)
        errExit("uname");
    printf("uts.nodename in child:  %s\n", uts.nodename);

    /* Keep the namespace open for a while, by sleeping.
        This allows some experimentation--for example, another
        process might join the namespace. */

    sleep(3);

    return 0; /* Child terminates now */
}

#define STACK_SIZE (1024 * 1024) /* Stack size for cloned child */

int main(int argc, char *argv[])
{
    char *stack;    /* Start of stack buffer */
    char *stackTop; /* End of stack buffer */
    pid_t pid;
    struct utsname uts;

    if (argc < 2)
    {
        fprintf(stderr, "Usage: %s <child-hostname>\n", argv[0]);
        exit(EXIT_SUCCESS);
    }

    /* Allocate stack for child */

    stack = malloc(STACK_SIZE);
    if (stack == NULL)
        errExit("malloc");
    stackTop = stack + STACK_SIZE; /* Assume stack grows downward */

    /* Create child that has its own UTS namespace;
        child commences execution in childFunc() */

    pid = clone(childFunc, stackTop, CLONE_NEWUTS | SIGCHLD, argv[1]);
    if (pid == -1)
        errExit("clone");
    printf("clone() returned %ld\n", (long)pid);

    /* Parent falls through to here */

    sleep(1); /* Give child time to change its hostname */

    /* Display hostname in parent's UTS namespace. This will be
        different from hostname in child's UTS namespace. */

    if (uname(&uts) == -1)
        errExit("uname");
    printf("uts.nodename in parent: %s\n", uts.nodename);

    if (waitpid(pid, NULL, 0) == -1) /* Wait for child */
        errExit("waitpid");
    printf("child has terminated\n");

    exit(EXIT_SUCCESS);
}
```

把上面的代码保存到 `main.c` 之后，使用命令 `gcc main.c -o clone-demo` 编译。

编译完成后，`sudo ./clone-demo new-hostname` 执行。

最终结果类似这样

```
DESKTOP-HEKKTQ9 :: ~/repos/container » sudo ./clone-demo new-hostname
clone() returned 1515
uts.nodename in child:  new-hostname
uts.nodename in parent: DESKTOP-HEKKTQ9
child has terminated
DESKTOP-HEKKTQ9 :: ~/repos/container »
```

### setns

`setns` 把调用这个函数的线程加入指定 fd 的命名空间里。这个 `fd` 指的是 `/proc/1234/ns/uts` 这些特殊文件的文件描述符。

举例来说，我们把 `clone-demo` 的源码里，`sleep(3)` 改为 `sleep(200)`，再执行`sudo clone-demo new-hostname &` 把进程放到后台。

然后编译下面的代码并测试加入 clone-demo 的 uts 名称空间。

```c
#define _GNU_SOURCE
#include <fcntl.h>
#include <sched.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#define errExit(msg)        \
    do                      \
    {                       \
        perror(msg);        \
        exit(EXIT_FAILURE); \
    } while (0)

int main(int argc, char *argv[])
{
    int fd;

    if (argc < 3)
    {
        fprintf(stderr, "%s /proc/PID/ns/FILE cmd args...\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    fd = open(argv[1], O_RDONLY); /* Get file descriptor for namespace */
    if (fd == -1)
        errExit("open");

    if (setns(fd, 0) == -1) /* Join that namespace */
        errExit("setns");

    execvp(argv[2], &argv[2]); /* Execute a command in namespace */
    errExit("execvp");
}
```

最终结果如下

```
root@DESKTOP-HEKKTQ9:/home/weakptr/repos/container# ./clone-demo new-hostname &
[1] 1826
clone() returned 1827
uts.nodename in child:  new-hostname
uts.nodename in parent: DESKTOP-HEKKTQ9

root@DESKTOP-HEKKTQ9:/home/weakptr/repos/container# ./setns-demo /proc/1827/ns/uts /bin/bash
root@new-hostname:/home/weakptr/repos/container# uname -n
new-hostname
root@new-hostname:/home/weakptr/repos/container# exit
root@DESKTOP-HEKKTQ9:/home/weakptr/repos/container# exit
DESKTOP-HEKKTQ9 :: ~/repos/container » uname -n
DESKTOP-HEKKTQ9
```

### unshare

> ```c
> #define _GNU_SOURCE
> #include <sched.h>
>
> int unshare(int flags);
> ```

`unshare` 用于主动解除当前进程或线程从父进程继承的执行上下文（例如命名空间）。

`unshare`的主要用途就是在不创建新的进程的前提下，控制自己的共享执行上下文（还是指命名空间）。

参数 `flags` 依然是 `CLONE_NEWNS` 这些常量。惯例还是有个 demo 。

```c
/* unshare.c

    A simple implementation of the unshare(1) command: unshare
    namespaces and execute a command.
*/
#define _GNU_SOURCE
#include <sched.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <wait.h>

/* A simple error-handling function: print an error message based
    on the value in 'errno' and terminate the calling process */

#define errExit(msg)        \
    do                      \
    {                       \
        perror(msg);        \
        exit(EXIT_FAILURE); \
    } while (0)

static void
usage(char *pname)
{
    fprintf(stderr, "Usage: %s [options] program [arg...]\n", pname);
    fprintf(stderr, "Options can be:\n");
    fprintf(stderr, "    -i   unshare IPC namespace\n");
    fprintf(stderr, "    -m   unshare mount namespace\n");
    fprintf(stderr, "    -n   unshare network namespace\n");
    fprintf(stderr, "    -p   unshare PID namespace\n");
    fprintf(stderr, "    -u   unshare UTS namespace\n");
    fprintf(stderr, "    -U   unshare user namespace\n");
    exit(EXIT_FAILURE);
}

int main(int argc, char *argv[])
{
    int flags, opt;

    flags = 0;

    while ((opt = getopt(argc, argv, "imnpuU")) != -1)
    {
        switch (opt)
        {
        case 'i':
            flags |= CLONE_NEWIPC;
            break;
        case 'm':
            flags |= CLONE_NEWNS;
            break;
        case 'n':
            flags |= CLONE_NEWNET;
            break;
        case 'p':
            flags |= CLONE_NEWPID;
            break;
        case 'u':
            flags |= CLONE_NEWUTS;
            break;
        case 'U':
            flags |= CLONE_NEWUSER;
            break;
        default:
            usage(argv[0]);
        }
    }

    if (optind >= argc)
        usage(argv[0]);

    if (unshare(flags) == -1)
        errExit("unshare");

    pid_t pid = fork();
    if (pid == 0)
    {
        printf("child process");
        execvp(argv[optind], &argv[optind]);
        errExit("execvp");
    }
    else
    {
        printf("waitpid %ld\n", pid);
        waitpid(pid, NULL, 0);
    }
}
```

保存成 `unshare.c`，使用`gcc unshare.c -o unshare` 编译。

之后可以通过下面的命令来检查效果。

```bash
sudo ./unshare -pm /bin/bash # 隔离 mount 和 pid 两个 namespace
waitpid 2178
root@DESKTOP-HEKKTQ9:/home/weakptr/repos/container# mount -t proc proc /proc
root@DESKTOP-HEKKTQ9:/home/weakptr/repos/container# ps -ef
UID        PID  PPID  C STIME TTY          TIME CMD
root         1     0  0 15:22 pts/0    00:00:00 /bin/bash
root         3     1  0 15:22 pts/0    00:00:00 ps -ef
root@DESKTOP-HEKKTQ9:/home/weakptr/repos/container#
```

需要注意几个点：

1. `unshare` 最后必须是 `fork` 新进程再 `execvp`，否则会出现 `cannot allocate memory` 错误
2. `unshare` 启动新的 `/bin/bash` 进程后，`/proc` 挂载点还没有真正隔离，此时可以手动使用 `mount -t proc proc /proc` 命令挂载当前命名空间的 `procfs`。
3. mount namespace 中挂载事件传播，可以查看文档 `man 7 mount_namespaces`。

debian系的 Linux 发行版在 util-linux 包里提供了一个 `unshare` 程序，比上面的 demo 更强大，甚至可以用一行命令实现一个基本的*容器*。

```bash
# 我在 workspace 目录里装了 busybox，所以能直接跑起来 chroot 和 /bin/ash
# busybox 的安装方法参考 busybox 源码目录下的 INSTALL 文件
# vim Config.in 修改 config STATIC 下的 default 为 y
# make defconfig && make && make install CONFIG_PREFIX=你的workspace目录
sudo unshare -pumf --mount-proc=workspace/proc chroot workspace /bin/ash
```

结果：

```
/ # ps -ef
PID   USER     TIME  COMMAND
    1 0         0:00 /bin/ash
    2 0         0:00 ps -ef
/ # ls
bin      linuxrc  proc     sbin     usr
/ # mount
proc on /proc type proc (rw,nosuid,nodev,noexec,relatime)
/ #
```

## 用 go 实现

### syscall

go 对系统调用其实做了不少封装，基本在 `os` 和 `syscall` 下，但有很多区别。比如在 go 里找不到 `clone`、`setns` 这些接口，取而代之的是 `os/exec` 下的 `Cmd` 结构。不过 `syscall.Unshare` 倒是很忠实的还原了。诸如 `CLONE_NEWNS` 这些常量也可以找到对应的 `syscall.CLONE_NEWNS`。

不重复上面的代码了，写一个简短的启动 busybox 容器的 go 程序。

```go
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"syscall"
)

var (
	flagBootstrap bool
)

func init() {
	flag.BoolVar(&flagBootstrap, "bootstrap", false, "bootstrap busybox container")
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}

func runBusybox() {
	fmt.Printf("Start `busybox ash` in process %d\n", os.Getpid())

	cmd := exec.Command("/bin/busybox", "ash")
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(cmd.Env, "PATH=/bin:/sbin:/usr/bin:/usr/sbin")

	must(syscall.Chroot("workspace"))
	must(os.Chdir("/"))
	must(syscall.Mount("proc", "/proc", "proc", 0, ""))
	must(cmd.Run())

	println("unmount proc")
	must(syscall.Unmount("proc", 0))
}

func runContainerizedCommand() {
	cmd := exec.Command("/proc/self/exe")
	cmd.Path = "/proc/self/exe"
	cmd.Args = append(cmd.Args, "-bootstrap")
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Cloneflags:   syscall.CLONE_NEWUTS | syscall.CLONE_NEWNS | syscall.CLONE_NEWPID,
		Unshareflags: syscall.CLONE_NEWNS,
	}

	fmt.Printf("starting current process %d\n", os.Getpid())
	must(cmd.Run())
}

func main() {
	flag.Parse()
	if flagBootstrap {
		runBusybox()
		return
	}

	runContainerizedCommand()
}
```

保存为 `demo.go` 后用 `go build -o demo demo.go` 编译，然后执行 `sudo ./demo` 。

结果像是这样：

```
DESKTOP-HEKKTQ9 :: ~/repos/container » sudo ./demo
starting current process 2954
Start `busybox ash` in process 1
/ # ps -ef
PID   USER     TIME  COMMAND
    1 0         0:00 /proc/self/exe -bootstrap
    6 0         0:00 /bin/busybox ash
    7 0         0:00 ps -ef
/ # mount
proc on /proc type proc (rw,relatime)
/ #
unmount proc
DESKTOP-HEKKTQ9 :: ~/repos/container »
```

## 总结

上面的 demo 仅仅是创建了一个看起来像容器的玩具，连 cgroup 都没有，距离真正的 OCI 运行时还有不小差距。不过已经足够展示创建一个隔离的环境并不是特别困难的事情，这必须感谢 Linux 内核的开发者们让容器技术有了存在的可能，而且还能这么简单地使用。

可以点击[这个链接]([runtime-spec/spec.md at master · opencontainers/runtime-spec (github.com)](https://github.com/opencontainers/runtime-spec/blob/master/spec.md))查看 OCI 运行时的规格说明。

涉及概念：

- namespace

重要系统调用

- `clone`
- `setns`
- `unshare`
- `mount`
- ...

本篇还不涉及网络，仅在文件系统和PID、用户等层级做了隔离。网络隔离可以参考 `man 7 network_namespaces` ，不过谷歌搜了一大圈也还没找到怎么创建虚拟网卡，暂且先放着了。

