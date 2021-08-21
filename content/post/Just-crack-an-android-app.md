---
title: 一个安卓应用的逆向分析
date: 2020-12-29 14:04:02
categories:
  - 逆向
tags:
  - 逆向
  - Java
  - C++
  - Android
password: v60x0x
abstract: 不想惹事，加密了。
references:
  - title: 分析Android APK-砸壳-Fdex2
    url: https://www.cnblogs.com/csharponworking/p/11665481.html
  - title: Xposed Framework API - IXposedHookLoadPackage
    url: https://api.xposed.info/reference/de/robv/android/xposed/IXposedHookLoadPackage.html
  - title: mitmproxy
    url: https://github.com/mitmproxy/mitmproxy/
---

说起来也不算什么新鲜的东西，现成的工具拼拼凑凑就搞定了，单纯算是点亮了新的技能。

待破解应用的名字不透露了，避免引火烧身。

需要准备的工具包括

- mumu 模拟器(或者别的什么有 root 权限、能装 xposed 的模拟器)
- FDex2 脱壳
- jadx 反编译 dex 源码
- apktools 拆解 apk
- mitmproxy 中间人拦截网络请求

<!-- more -->

## 0x01 目标和方向选择

首要的目标是破解这个软件的 api 加密。

使用 mitmproxy 抓到 https 流量，发现请求体全部是 base64 ，解码发现乱码。基本断定是加密了。

> mitmproxy 怎么抓 https 流量不多说了，基本流程就是装证书，然后配置代理。能看到有流量进 mitmproxy 就算成功了。
>
> 直接参考 mitmproxy 的文档快一点。

{% asset_img 01.png encrypted %}

搜了一圈没有什么现成的对这个 App 的破解的文章，于是决定自己动手。

## 0x02 解包和脱壳

先确认下电脑上装了 JDK 或者 JRE ，没有的话就装好。

推荐一个 vscode 的插件，`apklab`。会帮你装好 jadx 和 apktools / signer 这些工具。

接下来直接用 `apklab` 打开需要破解的 apk 文件。

{% asset_img 02.png %}
{% asset_img 03.png %}
{% asset_img 04.png %}

apklab 会自动用 apktools 和 jadx 完成拆包和反编译。

然后简单观察...

{% asset_img 05.png %}

应该是被 360 加固了。

apk 加固的基本原理就是把易被反编译的 java 字节码转译或者加密后保存，运行的时候再释放出来。用过 upx 一类的软件应该会联想到，就是加壳、反调试什么的这一套。

xposed 提供了一个[在安卓包加载时设置钩子的机会](https://api.xposed.info/reference/de/robv/android/xposed/IXposedHookLoadPackage.html)，将 ClassLoader Hook 掉，以此获得真正的应用字节码。

代码看参考资料。

安装 xposed 框架和 FDex2 之后启动目标应用，即可获得对应的字节码 dex 文件。

{% asset_img 06.png %}
{% asset_img 07.png %}

接着把这些 dex 文件复制出来，即可使用 jadx 反编译到 java 了。

```shell
jadx -d out *.dex
```

将反编译的结果用 vscode 打开，可以看到目标已经被我们脱干净了。

{% asset_img 08.png %}

## 0x03 寻找加解密代码

目标是解密 Api 请求的内容，所以下一步就是找到哪里保存了加密代码。

幸运的是这个 App 没有做过混淆，完成脱壳后就已经是全身赤裸的站在我们面前了。

直接在代码里搜索之前我们观察到的 url：`index_des.php`，仅有一个结果。

{% asset_img 09.png %}

相关函数非常短，这个 HTTP 框架我没有使用过，不过从函数名看应该是一个中间件模式，对所有 Web 请求进行加密处理。

{% asset_img 10.png %}

`getOverPost2` 源码如下

{% asset_img 11.png %}

从代码里可以得出：

- g 的含义是 Get 请求的参数，应该就是 QueryString。函数名 `getOverPost2` 字面意义就是把 GET 请求以 POST 方式发送出去。
- p 的含义大概就是 Post 的参数了。
- 加密代码在 `encryptByte`

如此看来已经接近终点了，再点开 `encryptByte` 的定义

{% asset_img 12.png %}

密钥保存在 `DesLib.sharedInstance().getAuthKey()` 中。

接着点开 `getAuthKey` 的定义:

{% asset_img 13.png %}

`native` 关键字一出，得，白高兴了。差点劝退成功。

还是先看下怎么加密的。

{% asset_img 14.png %}

再往回翻一下响应解密的代码，免得拆除密钥来又白高兴一场。

{% asset_img 15.png %}
{% asset_img 16.png %}

很好，也是 DES 。

其实到这一步已经基本完成解密了，唯一欠缺的就是密钥。

抱着试一试的心情，还是找到了 `libencry.so` ，用 IDA 打开分析了一下。

{% asset_img 17.png %}

一通操作猛如虎，结果发现看不懂汇编。=w=

按下 F5，看看伪代码。

{% asset_img 18.png %}

还是看不懂。这都调的什么函数... `a1 + 668` 这个蜜汁偏移也不知道是在算什么。

网上搜索了一圈，说道可以手动改一下函数签名，IDA 就能提示出函数了。试试看。

先把函数签名纠正

{% asset_img 19.png %}
{% asset_img 20.png %}

再关掉类型转换

{% asset_img 21.png %}

最终关键代码清晰了很多，看起来就是个直接返回字符串常量的函数。

{% asset_img 22.png %}

比较具有迷惑性的是上面的 v5-v9，可以看到 v5-v9 地址是增长、连续的，只有 v5 和 v6 有值。v7/v8/v9 都是 0 。而 v5 的地址被用作 `NewStringUTF` 函数的参数。查阅 JNI 接口也可以看到这个参数应该是 `const char*` 类型。

所以 ...

把数值转换成 16 进制再做观察。

{% asset_img 23.png %}

发现很有规律，每个字节的值都在 ASCII 范围内。于是右键转换成字符串，再按字节序翻转一下，即可得到密钥。

到此，解密方法的探索已经完成。

## 0x04 mitmproxy 解密

mitmproxy 支持使用 python 脚本扩展，用法很简单就是 `mitmweb.exe -s decrypt.py`

可以参考 mitmproxy 的[例子](https://github.com/mitmproxy/mitmproxy/blob/master/examples/addons/contentview.py)

最终效果应该是这样

{% asset_img 25.png %}

核心的解密代码就一句，利用 mitmproxy 的扩展即可对每个请求进行统一的处理。

```python
from pyDes import des, PAD_PKCS5

def decrypt(data: Union[str, bytes]) -> bytes:
    return des(key).decrypt(data, padmode=PAD_PKCS5)
```

## 0x05 结语

这个破解的最大意义还是完成了一次完整的安卓逆向，算是点亮了新技能。

以后再遇到一些傻逼软件或者强制推广的东西就可以用这一手技能来研究吐槽下都什么傻逼代码了。

当然非法的事情是不可能做的。

这玩意儿破解完之后发现有泄露隐私、被脱裤的严重漏洞，我也给市政平台发了件。

所以明年如果再硬推一次的话，到时候再拆了看看是不是有点长进。当然，没人管应该才是常态。

要是有关部门不管，开发的公司也不管，那我也没办法，我还年轻，也不想因为这个吃牢饭。
