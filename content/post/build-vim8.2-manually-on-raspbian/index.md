---
title: 在raspbian上手动编译vim8.2
slug: build-vim8.2-manually-on-raspbian
date: 2021-12-25 10:37:00
categories:
- linux运维
tags:
- linux运维
- raspberry-pi
- raspbian
- vim
---

## 前言

raspbian上自带的vim版本还是低了点，像是`coc.nvim`之类的插件弹警告就搞得很烦。我寻思自己编译一个吧。

## 0x01 下载源码

从[vim官网](https://www.vim.org/download.php)下载源码（或者可以从GitHub下，出于网络考虑还是直接从ftp下了），下完直接`scp`传到树莓派上，`tar xf`解压好准备开整。

## 0x02 配置

惯例先看看文档，`README.md`里指出源码安装去看`src/INSTALL`，所以跟着去看。

在 Unix 一节中提到直接`make`+`make install`就完事，但我要的不是编译个默认版本的vim，毕竟还有插件会用到`vim`的 `Pyhon`/`Python3` 特性，比如`ycm`。

继续往下翻会看到编译依赖。

	% sudo apt install git
	% sudo apt install make
	% sudo apt install clang
	% sudo apt install libtool-bin

跟着把依赖装好，clang估计是可选项，gcc肯定是能编译vim的。不过以防万一反正全装上。

后面终于看到了Python3添加支持的方式。

	Add Python 3 support:
	% sudo apt install libpython3-dev
	Uncomment this line in Makefile:
		"CONF_OPT_PYTHON3 = --enable-python3interp"
	% make reconfig

虽然说文档让取消注释，但是我不想改东西。所以记一下`--enable-python3interp`，等会儿加入`configure`的参数。

后面又有个关于gui的，因为不使用gui，所以也记一下。

> Unix: COMPILING WITH/WITHOUT GUI
>
> NOTE: This is incomplete, look in Makefile for more info.
>
> These configure arguments can be used to select which GUI to use:
>
> ```
> --enable-gui=gtk      or: gtk2, motif, athena or auto
> --disable-gtk-check
> --disable-motif-check
> --disable-athena-check
> ```
>
> This configure argument can be used to disable the GUI, even when the necessary
> files are found:
>
> ```
> --disable-gui
> ```

到时候`--disable-gui`可以省一点编译时间，虽然本来也没多少编译时间。树莓派性能不是很好，tf卡读写寿命也有限，省一点是一点咯。

还有个`--with-features=big`，实际参考[vim's versions and features](http://www.drchip.org/astronaut/vim/vimfeat.html)，还是用`huge`，因为看起来功能比较全。

再加上参数`--enable-multibyte`和`--enable-cscope`就差不多了。再加上必要的一些依赖库。

```shell
sudo apt install -y libpython-dev libpython3-dev libperl-dev libncurses-dev
```

## 0x03 编译

按照`autoconf`这套编译系统的常规套路，先运行`./configure`，带上之前考虑好的参数。

```shell
./configure \
	--prefix=/usr/local/ \
	--with-features=huge \
	--enable-multibyte \
	--disable-gui \
	--enable-pythoninterp \
	--enable-python3interp \
	--enable-perlinterp \
	--enable-cscope
```

最后

```shell
make
sudo make install
```

等编译完成。

## 0x04 设置默认编辑器

用`update-alternatives`配置默认编辑器，或者在`.zshrc`里加上`alias vim=/usr/local/bin/vim`也是可以的。

```shell
sudo update-alternatives --install /usr/bin/editor editor /usr/local/bin/vim 1
sudo update-alternatives --set editor /usr/local/bin/vim
sudo update-alternatives --install /usr/bin/vi vi /usr/local/bin/vim 1
sudo update-alternatives --set vi /usr/local/bin/vim
```

## 总结

vim的编译这么简单应该把功劳算到良好的架构上，功能开关这种东西是要架构清晰地给组件之间划出边界的。

很多杂鱼公司根本不考虑系统维护，所谓的 **创造价值** 就是以最快的速度 **应付需求** ，想起几年前的自己还真的是天真，以为软件从业起码是有点基本的素养的，起码工程能力是有的。现在我的想法变了，软件从业不是有手就行？产品最想要的就是直接把别家的软件 *copy&paste* 成自己的，我寻思做软件键盘上磨损最快的就是 `ctrl` `c` `v`这三个键了。

产品嘛。什么工程性？什么可维护？那跟我有什么关系，反正改需求的dead line是码农的，修bug是码农修，我产品设计要与时俱进，要紧随市场，要服务客户，你就是个写代码的，这也不做那也不做雇你来干什么？

平常心平常心，扯远了。

总之，vim，好软件。顺便记得关注下乌干达儿童生存状况（不扯政治地说，vim自称慈善软件(charityware)还是有点东西的，再说下去鲁迅先生就要出来赶苍蝇了）。