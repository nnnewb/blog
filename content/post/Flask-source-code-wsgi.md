---
title: Flask源码阅读笔记：WSGI
tags:
  - python
  - flask
categories:
  - python
date: 2019-03-17 00:00:00
---

## 0. Intro

Flask 是一个基于 WSGI 协议的上层应用框架，据我了解应该是和 Tornado、Django 流行程度相近，当然 Django 老大哥始终占据了最多的份额。Flask 是一个轻量级的 Micro Framework，源码值得一读。

## 1. 回顾 WSGI

开始之前，需要先回顾以下 WSGI 协议。

WSGI 是一个针对 Python 的协议，故说到的 App、Server、函数、参数等描述都是指 Python 对应的概念或实现。

### 1.1 PEP-0333 到 PEP-3333

PEP-0333 是初版的 WSGI 协议提案，PEP-3333 是 1.0.1 版本的 WSGI 提案，差别不大，主要是对 py3 和 py2 不兼容的部分作了更新说明（`str`和`unicode`方面的问题，python2 的 str 在 python3 是 bytes，故 python3 编写的 wsgi app 必须返回 bytes）。

WSGI 协议规范了 Python Web 应用的两个层级：服务器层（Server）和应用层（Application），两者通过 WSGI 协议进行通信。

其中 Server 负责处理请求，将请求转换成符合 WSGI 要求的模式（`environ`参数）。 Application 完成处理后再通知 Server 返回 Response（`start_response`参数）。

WSGI 规定 App 必须是一个可以被调用的对象，接受指定数量的参数，WSGI Server 不关注任何其他 App 实现细节。而 WSGI App 也应当遵守这一要求，对 `start_response` 参数也遵守不依赖于任何 WSGI Server 的实现细节。

WSGI App 的接口规范声明如下。

```python
def app(environ, start_response): ...
```

`start_response`的声明如下。

```python
def start_response(status, response_headers, exc_info=None): ...
```

### 1.2 WSGI Server

常见的 WSGI Server 有几个。Nginx 和 Apache 都有 WSGI 插件，除此之外还有 gunicorn、gevent.wsgi 等。

举一个典型的例子来说。

```python
# app.py
import wsgiserver

def app(environ, start_response):
    start_response('200 OK', [('Content-Type','text-plain')])
    return [b"Hello world!"]

wsgiserver.WSGIServer(app, host='127.0.0.1', port='5000').start()
```

在 windows 下使用如下命令安装 wsgiserver

```bash
pip install wsgiserver
```

最后执行

```bash
python app.py
```

## 2. 入口点

看完 WSGI ，接下来看 Flask 请求的入口点在哪儿。

### 2.1 WSGI Server 与 `.run`

`Flask`这个类定义于`flask.app`，看这里的代码。

```python
class Flask(_PackageBoundObject):
    ...
```

先不去管 `_PackageBoundObject` 是啥。我们知道 `Flask`有一个`run`方法可以快速启动服务，直接跳转到那儿。

> [flask/app.py](https://github.com/pallets/flask/blob/master/flask/app.py)
> COMMIT a74864e , Line 844 ~ 949
>
> ```python
>     def run(self, host=None, port=None, debug=None, load_dotenv=True, **options):
>         """ 略 """
>         # Change this into a no-op if the server is invoked from the
>         # command line. Have a look at cli.py for more information.
>         if os.environ.get('FLASK_RUN_FROM_CLI') == 'true':
>             from .debughelpers import explain_ignored_app_run
>             explain_ignored_app_run()
>             return
>
>         if get_load_dotenv(load_dotenv):
>             cli.load_dotenv()
>
>             # if set, let env vars override previous values
>             if 'FLASK_ENV' in os.environ:
>                 self.env = get_env()
>                 self.debug = get_debug_flag()
>             elif 'FLASK_DEBUG' in os.environ:
>                 self.debug = get_debug_flag()
>
>         # debug passed to method overrides all other sources
>         if debug is not None:
>             self.debug = bool(debug)
>
>         _host = '127.0.0.1'
>         _port = 5000
>         server_name = self.config.get('SERVER_NAME')
>         sn_host, sn_port = None, None
>
>         if server_name:
>             sn_host, _, sn_port = server_name.partition(':')
>
>         host = host or sn_host or _host
>         port = int(port or sn_port or _port)
>
>         options.setdefault('use_reloader', self.debug)
>         options.setdefault('use_debugger', self.debug)
>         options.setdefault('threaded', True)
>
>         cli.show_server_banner(self.env, self.debug, self.name, False)
>
>         from werkzeug.serving import run_simple
>
>         try:
>             run_simple(host, port, self, **options)
>         finally:
>             # reset the first request information if the development server
>             # reset normally.  This makes it possible to restart the server
>             # without reloader and that stuff from an interactive shell.
>             self._got_first_request = False
> ```

首先进入眼帘的是关于 flask/cli 的内容。 点进 `explain_ignored_app_run` 可以得知这是一个防止用户犯蠢写下 app.run() 后又用 `flask run`在命令行启动留下的说明性输出。

其次是 dotenv 相关的玩意儿，没用过 dotenv 推荐去了解下 python-dotenv 这个包。可以很方便地配置好开发环境下的环境变量。

经过一堆类型转换和检查之后，终于看到了这几行。

> [flask/app.py](https://github.com/pallets/flask/blob/master/flask/app.py)
> COMMIT a74864e , Line 941 ~ 949
>
> ```python
>         from werkzeug.serving import run_simple
>
>         try:
>             run_simple(host, port, self, **options)
>         finally:
>             # reset the first request information if the development server
>             # reset normally.  This makes it possible to restart the server
>             # without reloader and that stuff from an interactive shell.
>             self._got_first_request = False
> ```

`run_simple`？这就是 WSGI Server 启动的地方了。

[看看 werkzeug 文档吧](http://werkzeug.pocoo.org/docs/0.14/serving/)，我这里摘一段。

> Serving WSGI Applications
> There are many ways to serve a WSGI application. While you’re developing it, you usually don’t want to have a full-blown webserver like Apache up and running, but instead a simple standalone one. Because of that Werkzeug comes with a builtin development server.
> The easiest way is creating a small start-myproject.py file that runs the application using the builtin server:
>
> ```python
> #!/usr/bin/env python
> # -*- coding: utf-8 -*-
>
> from werkzeug.serving import run_simple
> from myproject import make_app
>
> app = make_app(...)
> run_simple('localhost', 8080, app, use_reloader=True)
> ```

从函数签名可以看得出，`run_simple`启动时，flask 将自己作为 wsgi app 参数传给了 werkzeug，不难猜测出，Flask 本身是一个可调用对象，即重写了 `__call__` 方法。

### 2.2 `__call__`

来到`__call__`，发现它调用了`self.wsgi_app`，本身没做任何事。

> [flask/app.py](https://github.com/pallets/flask/blob/master/flask/app.py)
> COMMIT a74864e , Line 2323 ~ 2327
>
> ```python
>     def __call__(self, environ, start_response):
>         """The WSGI server calls the Flask application object as the
>         WSGI application. This calls :meth:`wsgi_app` which can be
>         wrapped to applying middleware."""
>         return self.wsgi_app(environ, start_response)
> ```

再来到 `wsgi_app` 的定义。

```python
    def wsgi_app(self, environ, start_response):
        """ 略 """
        ctx = self.request_context(environ)
        error = None
        try:
            try:
                ctx.push()
                response = self.full_dispatch_request()
            except Exception as e:
                error = e
                response = self.handle_exception(e)
            except:
                error = sys.exc_info()[1]
                raise
            return response(environ, start_response)
        finally:
            if self.should_ignore_error(error):
                error = None
            ctx.auto_pop(error)
```

这里，就是整个 Flask 作为 wsgi app，处理 request 的入口点了。

从这儿我们能鸟瞰整个 flask 框架的核心逻辑。`environ`被包装成 `request`，压栈，`full_dispatch_request`路由至视图，处理异常，一切结束后清栈。
