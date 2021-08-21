---
title: unity3d 键盘控制移动
author: weak_ptr <weak_ptr@outlook.com>
tags:
  - unity3d
  - "c#"
categories:
  - unity3d
date: 2018-12-17 02:29:00
---

```c#
void HandleKeyboardAction()
{
    var horizontal = Input.GetAxis("Horizontal") * PlayerMotionScaleLevel * Time.deltaTime;
    var vertical = Input.GetAxis("Vertical") * PlayerMotionScaleLevel * Time.deltaTime;
    var motion = transform.rotation * new Vector3(horizontal, 0, vertical);
    var mag = motion.magnitude;
    motion.y = 0;
    Player.transform.position += motion.normalized * mag;
}
```

极其简单的做法，获取到键盘移动的轴之后，用摄像机的旋转四元数乘一下，即可得到旋转后的向量，加上去就 ok 了。

需要注意的是这里用摄像机的四元数旋转要求摄像机必须只在 x 和 y 两个轴旋转。

先备份一下三维向量的数量值，这是为了能保证摄像机向上和向下看时，平面 x 和 z 轴上的分量不会过小，保持一致的移动速度。

用四元数旋转完成后，去除 y 轴的值，使目标只在当前平面上移动。再用算出来的向量的单位向量乘上之前备份的数量值，得到平面上移动的偏移向量。

最后，算出新的位置坐标。
