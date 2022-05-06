---
title: 一个有点离谱的trick
slug: a-trick-that-was-a-bit-off
date: 2022-05-06 11:06:52
categories:
- security
tags:
- security
- php
---

## 前言

打 red tiger 靶场的时候遇到一个有点怪的 trick ，慢慢道来。

level 3 里会拿到一个 php 文件，里面有加密/解密算法。算法本身不算怪，就是个简单的 xor ，比较怪的是秘钥流的生成算法，还有涉及到的密码学内容。

## 正文

### 解密算法

先看解密的算法。

```php
function decrypt ($str)
{
    srand(3284724);
    if(preg_match('%^[a-zA-Z0-9/+]*={0,2}$%',$str))
    {
        $str = base64_decode($str);
        if ($str != "" && $str != null && $str != false)
        {
            // 前面都是参数验证，下面才是真正的解密
            $decStr = "";

            // 把字符串按3个字符一组分割
            // 比如 123456789 分割成数组 123,456,789
            // 密文每3位表示一个明文字符
            for ($i=0; $i < strlen($str); $i+=3)
            {
                $array[$i/3] = substr($str,$i,3);
            }

            // 有趣的地方：伪随机数 xor 密文完成解密。
            foreach($array as $s)
            {
                $a = $s ^ rand(0, 255);
                $decStr .= chr($a);
            }

            return $decStr;
        }
        return false;
    }
    return false;
}
```

我加了点注释。接着说说为什么有趣。

### 伪随机数

> 口胡警告。

首先显而易见，接触过随机数函数都应该知道什么叫 *伪随机* ，基本伪随机数函数的文档都会给个密码学相关的警告，一般说的是这个函数不能生成在密码学而言安全的随机数。php 的 `rand` 函数也有个这样的警告。

> This function does not generate cryptographically secure values, and should not be used for cryptographic purposes. If you need a cryptographically secure value, consider using [random_int()](https://www.php.net/manual/en/function.random-int.php), [random_bytes()](https://www.php.net/manual/en/function.random-bytes.php), or [openssl_random_pseudo_bytes()](https://www.php.net/manual/en/function.openssl-random-pseudo-bytes.php) instead.

这就涉及所谓 *伪随机* 的本质了。伪随机数之所以是 *伪*  的，是因为其内部实现是一个让生成数字尽可能平均地分布到值域里的算法，如果给定输入则经过这个算法会得到固定的输出序列。对于不够强的伪随机数算法，得到一定数量的随机值后可以猜出随机种子或未来会出现的某个随机值的话，显然是不安全的。比如用作秘钥生成或者 `nonce` 之类的场景。

不过提到“不够强”，自然也有够强的伪随机数算法。也就是密码学安全的伪随机数生成器 *cryptographically-secure pseudorandom number generator, CSPRNG or CPRNG*。参考 wiki 定义如下。

> 除了满足统计学伪随机性外，还需满足“不能通过给定的随机序列的一部分而以显著大于 1/2 的概率在多项式时间内演算出比特序列的任何其他部分。”

真的不是很懂所以就不瞎扯了，继续说为啥有意思。`rand` 函数产生的是一个 **随机序列** ，然后这个序列被用来加密和解密，而且这个随机序列理论上来说是无限长的，而前述解密算法利用随机序列作为秘钥流解密密文。这就让人想到了另一个有意思的事情，*一次一密*。

### 一次一密

密码学入门教材应该有说过，一次一密是无条件安全的，统计学攻击对一次一密无效。但一次一密的难点在于如何传递或约定秘钥流，毕竟密文可以无条件安全，秘钥传递不行。如果是约定一个很长的秘钥流重复使用，那一次一密就退化成了MTP，获取到足够数量的密文还是可以被攻击。

上面的解密算法有趣的地方就在于使用了 `rand` 产生的随机数序列作为秘钥，如果再稍微改进一下，`$_SESSION`里记录`rand`的步数，完全可以实现伪一次一密，每次返回给浏览器的密文都不相同，凭密文也找不出规律。不过这样靶场难度就太高了=。=对我来说。

对上面给出的解密算法只能算是 MTP，虽然秘钥长度是无限的，但加密总是在用前 N 个数当秘钥。如果已知明文再多一点的话即使不拿到这个加密/解密算法也可以简单拼凑下密文发起攻击（因为 xor 是简单的替代密码，没有置换）。

### 随机数平台/版本差异

回到题目本身，这个解密算法其实不是那么可移植。我验证了一下，在 Windows 下 php 5.4 `rand` 产生的序列和 Linux 下 php 5.6 `rand` 产生的序列是不同的。直接把上面的解密算法在 Windows 下跑无法正常解密。

同时，php 5 的随机数算法和 php 7/8 的随机数算法又不一样，产生的序列不同。升级 php 版本也会导致原先加密的内容无法解密。

最终用在线沙盒解决了问题。

## 总结

代码跑不起来注意下平台和版本差异，我觉得干过几年自己搭过项目环境都应该知道怎么回事吧......

其他就是闲扯淡没什么好总结的，密码学的东西只看了点基础的，写不出证明也没怎么接触过什么正经实现。非要说的话就是比啥也不懂好一点。
