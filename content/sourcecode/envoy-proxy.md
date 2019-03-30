---
layout:     post

title:      "Istio实战系列-Envoy Proxy构建分析"
subtitle:   ""
excerpt: ""
author:     "赵化冰"
date:       2018-10-29
description: "Istio由控制面和数据面组成。其中Envoy是Istio在数据面缺省使用的转发代理，Istio利用Envoy的四层和七层代理功能对网格中微服务之间的调用流量进行转发。今天我>们来分析一下Istio 使用到的Envoy构建流程。"
image: "https://zhaohuabing.com/img/2018-10-29-envoy-build/background.jpg"
published: true 
tags:
    - Istio 
    - Envoy
    - Service Mesh 

categories: [ Tech ]
---

Istio由控制面和数据面组成。其中Envoy是Istio在数据面缺省使用的转发代理，Istio利用Envoy的四层和七层代理功能对网格中微服务之间的调用流量进行转发。今天我们来分析一下Istio 使用到的Envoy构建流程。

https://github.com/istio/proxy 这个库中包含了Istio对Envoy的扩展，包括用于对接Mixer的Filter和安全认证的Filter。但这个库中并不包含Envoy自身的源代码，因此这个库在构建时会从Github上下载Envoy源码进行联合编译。


# 编译工具

Envoy采用了Bazel进行构建。 Bazel是一种高层构建语言，类似Make，Maven和Gradle。其特点是可读性较好，支持跨语言，跨平台编译；并且可以定义代码库之间的依赖关系，支持跨代码库的联合构建。Bazel定义构建的依赖关系和规则，并管理构建生成的临时文件及二进制文件，具体的编译工作是调用各个语言的编译工具如GCC, JAVAC等完成的。

为了理解Envoy的编译过程，我们需要先了解Bazel的几个基础概念

* workspace: 文件系统中的一个目录，该目录中包含了用于编译软件所需的所有源文件。每个工作空间中有一个WORKSPACE文件，该文件用于描述该工作空间的外部依赖，例如依赖的Github上的第三方代码。

* Package: 是一组用于相关文件的集合，该目录中包含一个BUILD文件，此文件中描述了该程序包的构建方式。

* target: 生成的目标，一般是一个lib或者二进制文件。 target是一个构建规则(build rule)的实例，一般包含构建所需的源文件，构建目标的名称。rule还可以嵌套，一个rule的输出文件可以作为另一个rule的输入文件。例如一个二进制文件编译的target可以依赖另一个target生成的lib。另外target还可以依赖外部Repository中的另一个target，这个外部Repository可以是文件系统上另一个文件夹下的项目，github的项目或者http下载的代码。外部Repository在WORKSPACE文件中进行定义。

# 编译Envoy

首先参考Bazel的官方文档安装Bazel，并且需要安装gcc等相关工具。

设置gcc及g++环境变量

```
export CC=/usr/bin/gcc-5; export CXX=/usr/bin/g++-5
```

下载源码并进行构建

```
git clone https://github.com/istio/proxy.git
cd proxy
make build_envoy
```

如果出现错误提示，一般是由于编译所需的软件未安装导致，请根据提示信息进行安装。

如果一切顺利，bazel会在proxy目录下创建一个目录链接bazel-bin，指向生成的二进制文件。

# 编译过程分析

源码目录结构如下，主要的构建逻辑在引号包含的文件中。

```
├── "BUILD"
├── "Makefile"
├── "WORKSPACE"
├── src
│   ├── envoy                               -- envoy filter 插件源码
│   │   ├── alts
│   │   │   ├── *.cc
│   │   │   ├── *.h
│   │   │   └── "BUILD"
│   │   ├── "BUILD"
│   │   ├── http
│   │   │   ├── authn                     --认证 filte
│   │   │   │   ├── *.cc
│   │   │   │   ├── *.h
│   │   │   │   └── "BUILD"
│   │   │   ├── jwt_auth                    --jwt 认证 filter
│   │   │   │   ├── *.cc
│   │   │   │   ├── *.h
│   │   │   │   └── "BUILD"
│   │   │   └── mixer                      --mixer filter，实现metrics上报，Quota(Rate Limiting (处理http协议) 
│   │   │       ├── *.cc
│   │   │       ├── *.h
│   │   │       └── "BUILD"
│   │   ├── tcp
│   │   │   └── mixer                      --mixer filter(处理tcp协议)
│   │   │       ├── *.cc
│   │   │       ├── *.h
│   │   │       └── "BUILD"
│   │   └── utils
│   │       ├── *.cc
│   │       ├── *.h
│   │       └── "BUILD"
│   └── istio
│       └── **
├── test
│   └── **
└── tools
    └── **
```

编译的入口是根目录下的Makefile文件

```
# Build only envoy - fast
build_envoy:
        CC=$(CC) CXX=$(CXX) bazel $(BAZEL_STARTUP_ARGS) build $(BAZEL_BUILD_ARGS) //src/envoy:envoy
        @bazel shutdown
```

从中可以看到，调用了bazel进行构建，其构建的target为 //src/envoy:envoy 。这是bazel的语法，表明调用src/envoy这个目录下BUILD文件中Envoy这个target。

打开src/BUILD文件，查看该target的内容

```
envoy_cc_binary(
    name = "envoy",
    repository = "@envoy",
    visibility = ["//visibility:public"],
    deps = [
        "//src/envoy/http/authn:filter_lib",
        "//src/envoy/http/jwt_auth:http_filter_factory",
        "//src/envoy/http/mixer:filter_lib",
        "//src/envoy/tcp/mixer:filter_lib",
        "//src/envoy/alts:alts_socket_factory",
        "@envoy//source/exe:envoy_main_entry_lib",
    ],
)
```

cc_binary表明该target对应的是c++二进制rule，其中deps部分是其依赖的其他target。前5个target都是本地依赖，对应到源码目录中的其他子目录下的BUILD文件，其中最后一个比较特殊，是一个外部依赖，该外部库为envoy。

外部库定义在根目录下的WORKSPACE文件中。

```
ENVOY_SHA = "de039269f54aa21aa0da21da89a5075aa3db3bb9"
http_archive(
    name = "envoy",
    strip_prefix = "envoy-" + ENVOY_SHA,
    url = "https://github.com/envoyproxy/envoy/archive/" + ENVOY_SHA + ".zip",
)
```

该文件通过http_archive定义了一个外部repository，bazel在执行//src/envoy:envoy这个target时，发现该target依赖这个外部repository，根据http_archive中的描述，从指定的url下载该依赖的源码，并进行编译。

编译过程中的依赖关系如下图所示：


![](https://zhaohuabing.com/img/2018-10-29-envoy-build/envoy-build.png)
