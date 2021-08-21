---
title: AudioContext技术和音乐可视化（1）
tags:
  - javascript
date: 2018-11-07 02:48:00
categories:
  - javascript
---

## Intro

因为自己搭了个博客，一时兴起，就想写个动态的博客背景。毕竟用 django 后端渲染，前端只有 jquery 和 bootstrap 已经够 low 了，虽说极简风格也很棒，但是多少有点亮眼的东西才好办不是吗。

转载注明来源。

为了方便讲解，整个思路分为两个部分：音乐播放和背景绘制。

## 一、音乐播放

### 1.1 AudioContext

概述部分懒得自己写，参考 MDN 的描述。

> **AudioContext**接口表示由音频模块连接而成的音频处理图，每个模块对应一个[`AudioNode`](https://developer.mozilla.org/zh-CN/docs/Web/API/AudioNode)。**AudioContext**可以控制它所包含的节点的创建，以及音频处理、解码操作的执行。做任何事情之前都要先创建**AudioContext**对象，因为一切都发生在这个环境之中。

### 1.2 浏览器支持状况

`AudioContext标准`目前还是草案，不过新 chrome 已经实现了。我使用的 chrome 版本如下。

```
版本 70.0.3538.77（正式版本） （64 位）
```

如果发现 console 报错或者其他问题请检查浏览器版本，所有支持的浏览器可以在这个[链接](https://developer.mozilla.org/en-US/docs/Web/API/AudioContext)查看。

### 1.3 AudioContext 和音频处理图

关于`AudioContext`我的了解不是很深入，所以只在需要用到的部分进行概述。

首先，关于**音频处理图**的概念。

这个名词不甚直观，我用过虚幻，所以用虚幻的`Blueprint`来类比理解。音频处理图，其实是一系列音频处理的模块，连接构成一张数据结构中的“图”，从一般使用的角度来讲，一个播放音频的图，就是`AudioSource -> AudioContext.destination`，两个节点构成的图。其中有很多特殊的节点可以对音频进行处理，比如音频增益节点`GainNode`。

对于音频处理的部分介绍就到这里为止，毕竟真的了解不多，不过从 MDN 的文档看，可用的处理节点还是非常多的，就等标准制订完成了。

### 1.4 加载音频文件并播放

音频文件加载使用典型的`JavaScript`接口`FileReader`实现。

一个非常简单的实例是这样

首先是 html 里写上 input

```html
<html>
  <body>
    <input type="file" accept="audio/*" onchange="onInputChange" />
  </body>
</html>
```

然后在 javascript 里读文件内容。

```javascript
function onInputChange(files) {
  const reader = new FileReader();
  reader.onload = (event) => {
    // event.target.result 就是我们的文件内容了
  };
  reader.readAsArrayBuffer(files[0]);
}
```

文件读取就是这么简单，所以回到那个问题：说了那么多，音乐到底怎么放？

答案是用`AudioContext`的`decodeAudioData`方法。

所以从上面的 js 里做少许修改——

```javascript
// 创建一个新的 AudioContext
const ctx = new AudioContext();

function onInputChange(files) {
  const reader = new FileReader();
  reader.onload = (event) => {
    // event.target.result 就是我们的文件内容了
    // 解码它
    ctx.decodeAudioData(event.target.result).then((decoded) => {
      // 解码后的音频数据作为音频源
      const audioBufferSourceNode = ctx.createBufferSource();
      audioBufferSourceNode.buffer = decoded;
      // 把音源 node 和输出 node 连接，boom——
      audioBufferSourceNode.connect(ctx.destination);
      audioBufferSourceNode.start(0);
      // 收工。
    });
  };
  reader.readAsArrayBuffer(files[0]);
}
```

### 1.5 分析频谱

频谱的概念我建议搜一下**傅里叶变换**，关于时域和频域转换的计算过程和数学原理直接略（因为不懂），至今我还只理解到时域和频域的概念以及傅里叶变换的实现接受采样返回采样数一半长的频域数据......

不班门弄斧了。

以前写`python`的时候用的`numpy`来进行傅里叶变换取得频域数据，现在在浏览器上用 js 着实有些难受。不过幸好，`AudioContext`直接支持了一个音频分析的 node，叫做`AudioAnalyserNode`。

这个 Node 处于音源 Node 和播放输出 Node 之间，想象一道数据流，音源 Node 把离散的采样数据交给 Analyser，Analyser 再交给输出 Node。

直接看代码实例。

```javascript
// 创建一个新的 AudioContext
const ctx = new AudioContext();
// 解码后的音频数据作为音频源
// 为了方便管理，将这些Node都放置在回调函数外部
const audioBufferSourceNode = ctx.createBufferSource();

// 创建音频分析Node!
const audioAnalyser = ctx.createAnalyser();
// 注意注意！这里配置傅里叶变换使用的采样窗口大小！比如说，我们要256个频域数据，那么采样就应该是512。
// 具体对应频率请自行搜傅里叶变换相关博文。
audioAnalyser.fftSize = 512;

function onInputChange(files) {
  const reader = new FileReader();
  reader.onload = (event) => {
    // event.target.result 就是我们的文件内容了
    // 解码它
    ctx.decodeAudioData(event.target.result).then((decoded) => {
      // 停止原先的音频源
      audioBufferSourceNode.stop();
      // 先把音频源Node和Analyser连接。
      audioBufferSourceNode.connect(audioAnalyser);
      // 然后把Analyser和destination连接。
      audioAnalyser.connect(ctx.destination);
      // 修改音频源数据
      audioBufferSourceNode.buffer = decoded;
      audioBufferSourceNode.start(0);
      // 收工。
    });
  };
  reader.readAsArrayBuffer(files[0]);
}

window.requestAnimationFrame(function () {
  // 读取频域数据
  const freqData = new Uint8Array(audioAnalyser.frequencyBinCount);
  console.log(freqData);
});
```

频域数据是二维的，频率（数组下标）和能量（下标对应值）。悄悄补一句，数学上应该说是该频率函数图像的振幅？

其实获得了这个频域数据，继续画出我们常见的条状频域图就很容易了。参考我一朋友的博客。[misuzu.moe](https://misuzu.moe/music/index.html)，可以看看效果。

关于`AudioContext`的介绍先到此为止，等我找时间继续写。

> PS：代码不保证复制粘贴就能运行，领会精神，遇到问题查查文档。MDN 比我这博客详细多了。
