---
title: 轻量级 django 阅读笔记：最小的 django 应用
tags: [python, django]
categories:
  - python
date: 2019-03-03 12:26:00
---

## Intro

找不到工作十分难受，在家看书，恰巧翻到这本《轻量级 Django》，看起来还蛮有意思的，做个读书笔记。

## 1. 最小的 Django App

Django 是个重量级框架，所谓最小指的是写最少的代码，理解一个 Django App 的最小组成元素。

作为开场，先创建一个 `app.py` 文件，作为整个 Django App 存储的地方。

### 1.1 django.conf.settings

书中使用 `django.core.management.execute_from_command_line` 作为启动 Django app 的手段。

`execute_from_command_line`，就是通过 `django startproject`的方式创建的`manage.py`内的主要内容，这种方式启动必须要配置`settings`才行。

在一个常规方式创建的 Django App 中，`settings.py`是一个独立的 python 模块，`Django`通过`DJANGO_SETTINGS_MODULE`这个环境变量来确定配置信息存储位置。

但是换一种方式，`django.conf.settings.configure()`可以手动完成配置。

看代码。

```python
from django.conf import settings

settings.configure(DEBUG=True, ROOT_URLCONF=__name__, )
```

每一个 keyword argument 都和 `settings.py`这个模块内的名字相同，去除所有不必要的元素之后，剩下的就是`DEBUG`和`ROOT_URLCONF`了。

阅读源码可知`configure`只能被调用一次。

```python
# 摘自 django.conf.settings.configure 源码
# Django 版本号:
# VERSION = (2, 1, 7, 'final', 0)

def configure(self, default_settings=global_settings, **options):
    """
    Called to manually configure the settings. The 'default_settings'
    parameter sets where to retrieve any unspecified values from (its
    argument must support attribute access (__getattr__)).
    """
    if self._wrapped is not empty:
        raise RuntimeError('Settings already configured.')
    holder = UserSettingsHolder(default_settings)
    for name, value in options.items():
        setattr(holder, name, value)
    self._wrapped = holder
```

### 1.2 urlpatterns

都知道 `Django` 的路由是需要手动写明的，和`flask`等以装饰器的方式配置路由的风格迥异。哪种风格更好，就看用户自己见仁见智了。

上文的`settings.configure`中可以看到有一句`ROOT_URLCONF=__name__`，意义明确，就是指定哪个 python 模块保存了路由配置信息，而这里指定的`__name__`正是自己。

所以我们的`urlpatterns`也应当如配置所述，写到这个文件中。

见代码。

```python
from django.urls import path
from django.http import HttpResponse

urlpatterns = [path('', lambda req: HttpResponse('Hello world'))]
```

### 1.3 `__main__`

最后将所有的代码整合起来，就形成了这样一个 python 程序。

```python
import sys

from django.conf import settings
from django.core.management import execute_from_command_line
from django.http import HttpResponse
from django.urls import path

settings.configure(DEBUG=True, ROOT_URLCONF=__name__, )

urlpatterns = [path('', lambda req: HttpResponse('Hello world'))]

if __name__ == '__main__': execute_from_command_line(sys.argv)
```

算上所有的 import 在内共 12 行，4 行空行，5 行 import，3 行代码，即构成了一个麻雀虽小五脏俱全的 Django hello world。

在命令行执行`python app.py runserver`即可看到以下输出。

```python
PS D:\GitHub\minimum-django> python .\app.py runserver
Performing system checks...

System check identified no issues (0 silenced).
March 03, 2019 - 12:10:21
Django version 2.1.7, using settings None
Starting development server at http://127.0.0.1:8000/
Quit the server with CTRL-BREAK.
```

### 1.4 wsgi

完成了最小的 django app，依然有一个问题。

如何部署这个 django app？

固然，使用 runserver 的方式执行，再 nginx 反向代理是一个不错的主意，但 uwsgi 之类的部署方式依然有其独到的优势。

使用 uwsgi 或者 gunicorn 之类的基于 wsgi 协议的服务器就必须取得一个 wsgi app 实例才行。

Django 提供了函数 `django.core.wsgi.get_wsgi_application` 用于取得 wsgi app。

手头没 linux 机器，懒得演示 output 了。就这样吧。

最终代码如下。

```python
import sys

from django.conf import settings
from django.core.management import execute_from_command_line
from django.core.wsgi import get_wsgi_application
from django.http import HttpResponse
from django.urls import path

settings.configure(DEBUG=True, ROOT_URLCONF=__name__, )

urlpatterns = [path('', lambda req: HttpResponse('Hello world'))]

application = get_wsgi_application()

if __name__ == '__main__': execute_from_command_line(sys.argv)
```

使用`gunicorn app.py --log-file=-`启动。
