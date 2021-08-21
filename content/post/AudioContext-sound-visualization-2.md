---
title: AudioContext 技术和音乐可视化（2）
tags:
  - javascript
categories:
  - javascript
date: 2018-11-08 21:41:00
---

## Intro

转载请注明来源，可以在[测试博客](https://th-zxj.club)查看完成效果。

本篇讲述如何从频域数据绘制动态的星空。

## 一、使用 Canvas 绘图

### 1.1 位置和大小

绘制背景的第一要务便是把 canvas 元素放置在背景这一层次上，避免遮盖其他元素。

对我而言，个人习惯用 css 来设置大小和位置，用 html 来确定渲染顺序而不是 z-index。

下面是 html 代码。

```html
<html>
  <body>
    <canvas id="background-canvas"></canvas>
    <!-- other elements -->
  </body>
</html>
```

下面是 css 代码。

```css
#background-canvas {
  position: fixed;
  left: 0;
  top: 0;
  width: 100vw;
  height: 100vh;
  background-color: black;
}
```

`fixed`确保拖动页面不会令背景也跟随移动。

其余部分我想应该没什么有疑问的地方。

### 1.2 CanvasContext2D

对于 canvas 元素的绘图操作我想很多人应该接触过。

以绘制圆形为例，使用如下代码。

```js
const canvas = document.getElementById("background-canvas");
const ctx = canvas.getContext("2d");

ctx.fillStyle = "#fff";
ctx.beginPath();
ctx.arc(100, 100, 50, 0, Math.PI * 2); // 参数分别为坐标x,y,半径，起始弧度，结束弧度
ctx.fill();
```

这样就画完了一个实心圆。

需要注意，canvas 的大小通过 css 设置可能导致画面被拉伸变形模糊，所以最好的办法是绘制前确定一下 canvas 的大小。

此外需要注意的是，重置大小会导致画面清空，用这种方式可以替代`fillRect`或者`clearRect`，有的浏览器平台更快但也有浏览器更慢。可以查阅这篇[博文](https://www.html5rocks.com/en/tutorials/canvas/performance/#toc-pre-render?tdsourcetag=s_pctim_aiomsg)来参考如何提升 canvas 绘图性能。

`fillStyle`可以使用 css 的颜色代码，也就是说我们可以写下诸如`rgba`、`hsla`之类的颜色，这给我们编写代码提供了很多方便。

### 1.3 绘制星星

星空是由星星组成的这显然不用多说了，先来看如何绘制单个星星。

星星的绘制方法很多，贴图虽然便利但显然不够灵活，我们的星星是要随节奏改变亮度和大小的，利用贴图的话就只能在`alpha`值和`drawImage`缩放来处理了。虽然是一种不错的办法，不过这里我使用了`RadialGradient`来控制绘图。

> PS：`RadialGradient` 的性能比较差，大量使用会导致明显的性能下降，这是一个显著降低绘制效率的地方。

那么，我们先画一个圆（加点细节预警）。

```js
const canvas = document.getElementById("background-canvas");
const ctx = canvas.getContext("2d");

// 确保不会变形
canvas.width = canvas.offsetWidth;
canvas.height = canvas.offsetHeight;

// 参数分别为起始坐标x,y,半径，结束坐标x,y,半径
const gradient = ctx.createRadialGradient(100, 100, 0, 100, 100, 50);
gradient.addColorStop(0.025, "#fff"); // 中心的亮白色
gradient.addColorStop(0.1, "rgba(255, 255, 255, 0.9)"); // 核心光点和四周的分界线
gradient.addColorStop(0.25, "hsla(198, 66%, 75%, 0.9)"); // 核心亮点往四周发散的蓝光
gradient.addColorStop(0.75, "hsla(198, 64%, 33%, 0.4)"); // 蓝光边缘
gradient.addColorStop(1, "hsla(198, 64%, 33%, 0)"); // 淡化直至透明
ctx.fillStyle = gradient;
ctx.beginPath();
ctx.arc(100, 100, 50, 0, Math.PI * 2);
ctx.fill();
```

可以在[codepen](https://codepen.io/weak_ptr/pen/KrzwPV)查看效果或直接编辑你的星（圈）星（圈）。

看上去还不错？

让我们用代码控制它的亮度和大小。

```js
const canvas = document.getElementById("background-canvas");
const ctx = canvas.getContext("2d");

// 确保不会变形
canvas.width = canvas.offsetWidth;
canvas.height = canvas.offsetHeight;

// 通过energy控制亮度和大小
let energy = 255;
let radius = 50;
let energyChangeRate = -1;

function draw() {
  requestAnimationFrame(draw); // 定时绘制，requestAnimationFrame比setTimeout更好。
  energy += energyChangeRate; // 见过呼吸灯吧？我们让它变亮~再变暗~反复循环~
  if (energy <= 0 || energy >= 255) energyChangeRate = -energyChangeRate;

  // 计算出当前的大小
  const r = radius + energy * 0.1;

  // 清空屏幕
  ctx.fillStyle = "black";
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  // 参数分别为起始坐标x,y,半径，结束坐标x,y,半径
  const gradient = ctx.createRadialGradient(100, 100, 0, 100, 100, r);
  gradient.addColorStop(0.025, "#fff"); // 中心的亮白色
  gradient.addColorStop(0.1, "rgba(255, 255, 255, 0.9)"); // 核心光点和四周的分界线
  gradient.addColorStop(
    0.25,
    `hsla(198, 66%, ${Math.min(75 + energy * 0.01, 100)}%, 0.9)`
  ); // 核心亮点往四周发散的蓝光
  gradient.addColorStop(
    0.75,
    `hsla(198, 64%, ${Math.min(33 + energy * 0.01, 100)}%, 0.4)`
  ); // 蓝光边缘
  gradient.addColorStop(1, "hsla(198, 64%, 33%, 0)"); // 淡化直至透明
  ctx.fillStyle = gradient;
  ctx.beginPath();
  ctx.arc(100, 100, r, 0, Math.PI * 2);
  ctx.fill();
}
draw();
```

可以在[codepen](https://codepen.io/weak_ptr/pen/LXNEaa)查看并编辑效果。

### 1.4 封装星星

通常来说粒子系统不大会把单个粒子封装成类，因为函数调用的开销还是蛮大的。。。

不过在这里我们这里就先这样了，方便理解和阅读。渲染的瓶颈解决之前，粒子函数调用这点开销根本不是回事儿。

```js
const canvas = document.getElementById("background-canvas");
const ctx = canvas.getContext("2d");

// 确保不会变形
canvas.width = canvas.offsetWidth;
canvas.height = canvas.offsetHeight;

// 用javascript原生的class而不是prototype
class Star {
  constructor(x, y, radius, lightness) {
    this.radius = radius;
    this.x = x;
    this.y = y;
    this.lightness;
  }

  draw(ctx, energy) {
    // 计算出当前的大小
    const r = this.radius + energy * 0.1;

    // 参数分别为起始坐标x,y,半径，结束坐标x,y,半径
    const gradient = ctx.createRadialGradient(
      this.x,
      this.y,
      0,
      this.x,
      this.y,
      r
    );
    gradient.addColorStop(0.025, "#fff"); // 中心的亮白色
    gradient.addColorStop(0.1, "rgba(255, 255, 255, 0.9)"); // 核心光点和四周的分界线
    gradient.addColorStop(
      0.25,
      `hsla(198, 66%, ${Math.min(75 + energy * 0.01, 100)}%, 0.9)`
    ); // 核心亮点往四周发散的蓝光
    gradient.addColorStop(
      0.75,
      `hsla(198, 64%, ${Math.min(33 + energy * 0.01, 100)}%, 0.4)`
    ); // 蓝光边缘
    gradient.addColorStop(1, "hsla(198, 64%, 33%, 0)"); // 淡化直至透明
    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.arc(this.x, this.y, r, 0, Math.PI * 2);
    ctx.fill();
  }
}

const star = new Star(100, 100, 50);

let energy = 255;
let energyChangeRate = -1;

// 渲染函数来循环渲染！
function render() {
  requestAnimationFrame(render);
  energy += energyChangeRate;
  if (energy <= 0 || energy >= 255) energyChangeRate = -energyChangeRate;
  // 清空屏幕
  ctx.fillStyle = "black";
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  star.draw(ctx, energy);
}

// 开始渲染动画！
render();
```

可以在[codepen](https://codepen.io/weak_ptr/pen/pQyJQQ)查看代码效果。

完成！

### 1.5 银河

绘制银河的核心在于随机分布的星星绕着同一中心点旋转，分为两步来讲，第一步是随机分布，这很简单，用`Math.random`就好了。

```js
// star 部分略

class Galaxy {
  constructor(canvas) {
    this.stars = [];
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");

    this.energy = 255;
    this.energyChangeRate = -2;
  }

  init(num) {
    for (let i = 0; i < num; i++) {
      this.stars.push(
        // 随机生成一定数量的星星，初始化星星位置和大小。
        new Star(
          Math.random() * this.canvas.width,
          Math.random() * this.canvas.height,
          Math.random() * 10 + 1,
          Math.random() * 30 + 33
        )
      );
    }
  }

  render() {
    this.energy += this.energyChangeRate;
    if (this.energy <= 0 || this.energy >= 255)
      this.energyChangeRate = -this.energyChangeRate;

    // 清空屏幕
    this.ctx.fillStyle = "black";
    this.ctx.fillRect(0, 0, canvas.width, canvas.height);

    for (const star of this.stars) {
      star.draw(this.ctx, this.energy);
    }
  }
}

const canvas = document.getElementById("background-canvas");
// 确保不会变形
canvas.width = canvas.offsetWidth;
canvas.height = canvas.offsetHeight;
const galaxy = new Galaxy(canvas);
galaxy.init(50);

function render() {
  requestAnimationFrame(render);
  galaxy.render();
}

render();
```

可以在[codepen](https://codepen.io/weak_ptr/pen/jQqPoQ)查看效果和完整代码。

### 1.6 旋转起来！

【加点细节预警】

接下来我们为星星准备轨道参数，让它们动起来！

首先修改`Star`类，加入几个字段。

```js
class Star {
  constructor(x, y, radius, lightness, orbit, speed, t) {
    this.radius = radius;
    this.x = x;
    this.y = y;
    this.lightness;
    this.orbit = orbit; // 轨道
    this.speed = speed; // 运动速度
    this.t = t; // 三角函数x轴参数，用 sin/cos 组合计算位置
  }
  // 下略
}
```

修改初始化代码。

```js
// 前略
  init(num) {
    const longerAxis = Math.max(this.canvas.width, this.canvas.height);
    const diameter = Math.round(
      Math.sqrt(longerAxis * longerAxis + longerAxis * longerAxis)
    );
    const maxOrbit = diameter / 2;

    for (let i = 0; i < num; i++) {
      this.stars.push(
        // 随机生成一定数量的星星，初始化星星位置和大小。
        new Star(
          Math.random() * this.canvas.width,
          Math.random() * this.canvas.height,
          Math.random() * 10 + 1,
          Math.random() * 30 + 33,
          Math.random() * maxOrbit, // 随机轨道
          Math.random() / 1000, // 随机速度
          Math.random() * 100 // 随机位置
        )
      );
    }
  // 后略
```

然后在`Galaxy`里加入控制移动的代码。

```js
move() {
    for (const star of this.stars) {
      console.log(star.orbit)
      star.x = this.canvas.width/2+ Math.cos(star.t) * star.orbit;
      star.y = this.canvas.height/2+ Math.sin(star.t) * star.orbit/2;
      star.t += star.speed;
    }
```

然后每一帧进行移动！

```js
function render() {
  requestAnimationFrame(render);
  galaxy.render();
  galaxy.move(); // 动起来！
}
```

大功告成！

在[codepen](https://codepen.io/weak_ptr/pen/NENGYm)查看完整源码！

### 1.7 待续

> PS：不保证粘贴的代码都能跑，反正 codepen 上是都能的。
