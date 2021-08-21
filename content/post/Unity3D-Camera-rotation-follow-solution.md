---
title: Unity3d 摄像机跟随旋转的方案
tags:
  - unity3d
  - 'c#'
date: 2018-11-03 18:20:00
categories:
- unity3d
---

## Intro

主要想探讨的是如何令摄像机随鼠标操作进行旋转和移动，摄像机跟随的脚本官方就有 Example。

## 方案：独立的角度变量

主要的特点是使用独立的角度变量，每次处理鼠标移动操作都会创建一个新的`Quaternion`用于计算。

先看 Demo。

```c#
public class PlayerControls : MonoBehaviour
{
    public GameObject Player;
    public float Distance;
    //public float CameraRepositionSpeed;
    public float MouseMotionScaleLevel;
    public bool ReverseAxisY;
    public float PitchMaximum;
    public float PitchMinimum;
    private float _CurrentCameraAngleAroundX;
    private float _CurrentCameraAngleAroundY;
    private Vector3 _PositionTarget;

    // Use this for initialization
    void Start()
    {
    }

    // Update is called once per frame
    void Update()
    {
        _CurrentCameraAngleAroundX += Input.GetAxis("Mouse Y") * MouseMotionScaleLevel * Time.deltaTime * (ReverseAxisY ? -1 : 1);
        _CurrentCameraAngleAroundY += Input.GetAxis("Mouse X") * MouseMotionScaleLevel * Time.deltaTime;
        _CurrentCameraAngleAroundX = Mathf.Clamp(_CurrentCameraAngleAroundX, PitchMinimum, PitchMaximum);
        _PositionTarget = Player.transform.position + Quaternion.Euler(_CurrentCameraAngleAroundX, _CurrentCameraAngleAroundY, 0) * (-Player.transform.forward * Distance);

        //transform.position = Vector3.Lerp(transform.position, _PositionTarget, Time.deltaTime * CameraRepositionSpeed);
        transform.position = _PositionTarget;
        transform.LookAt(Player.transform);
    }
}
```

核心在于`_CurrentCameraAngleAroundX`和`_CurrentCameraAngleAroundY`以及`Distance`，这三个变量共同决定了以玩家`Player`为原点的极坐标系下摄像机所处的空间位置。

计算坐标时只需要通过`Quaternion.Euler`来取得旋转四元数，以玩家为原点衍生一条（0,0,-1）的向量并乘上四元数以旋转至`Player`指向摄像机的方向，最后乘上`Distance`，即可得到摄像机相对玩家的偏移。

```c#
_PositionTarget = Player.transform.position +
    Quaternion.Euler(_CurrentCameraAngleAroundX, _CurrentCameraAngleAroundY, 0) *
    (-Player.transform.forward * Distance);
```

最后只要将摄像机放置在那个位置，然后`LookAt`旋转到`z`轴正方向指向玩家就完事儿了。
