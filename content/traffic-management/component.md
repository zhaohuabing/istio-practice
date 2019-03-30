# Istio流量管理相关组件

我们可以通过下图了解Istio流量管理涉及到的相关组件。虽然该图来自Istio Github old pilot repo, 但图中描述的组件及流程和目前Pilot的最新代码的架构基本是一致的。

![](https://zhaohuabing.com/img/2018-09-25-istio-traffic-management-impl-intro/traffic-managment-components.png)  
<center>Pilot Design Overview (来自[Istio old_pilot_repo](https://github.com/istio/old_pilot_repo/blob/master/doc/design.md)<sup>[[4]](#ref04)</sup>)</center>

图例说明：图中红色的线表示控制流，黑色的线表示数据流。蓝色部分为和Pilot相关的组件。

从上图可以看到，Istio中和流量管理相关的有以下组件：

## 控制面组件

### Discovery Services

对应的docker为gcr.io/istio-release/pilot,进程为pilot-discovery，该组件的功能包括：

* 从Service  provider（如kubernetes或者consul）中获取服务信息
* 从K8S API Server中获取流量规则(K8S CRD Resource)
* 将服务信息和流量规则转化为数据面可以理解的格式，通过标准的数据面API下发到网格中的各个sidecar中。

### K8S API Server

提供Pilot相关的CRD Resource的增、删、改、查。和Pilot相关的CRD有以下几种:

* **Virtualservice**：用于定义路由规则，如根据来源或 Header 制定规则，或在不同服务版本之间分拆流量。
* **DestinationRule**：定义目的服务的配置策略以及可路由子集。策略包括断路器、负载均衡以及 TLS 等。
* **ServiceEntry**：用 [ServiceEntry](https://istio.io/docs/reference/config/istio.networking.v1alpha3/#ServiceEntry) 可以向Istio中加入附加的服务条目，以使网格内可以向istio 服务网格之外的服务发出请求。
* **Gateway**：为网格配置网关，以允许一个服务可以被网格外部访问。
* **EnvoyFilter**：可以为Envoy配置过滤器。由于Envoy已经支持Lua过滤器，因此可以通过EnvoyFilter启用Lua过滤器，动态改变Envoy的过滤链行为。我之前一直在考虑如何才能动态扩展Envoy的能力，EnvoyFilter提供了很灵活的扩展性。

## 数据面组件

在数据面有两个进程Pilot-agent和envoy，这两个进程被放在一个docker容器gcr.io/istio-release/proxyv2中。

### Pilot-agent

该进程根据K8S API Server中的配置信息生成Envoy的配置文件，并负责启动Envoy进程。注意Envoy的大部分配置信息都是通过xDS接口从Pilot中动态获取的，因此Agent生成的只是用于初始化Envoy的少量静态配置。在后面的章节中，本文将对Agent生成的Envoy配置文件进行进一步分析。

### Envoy

Envoy由Pilot-agent进程启动，启动后，Envoy读取Pilot-agent为它生成的配置文件，然后根据该文件的配置获取到Pilot的地址，通过数据面标准API的xDS接口从pilot拉取动态配置信息，包括路由（route），监听器（listener），服务集群（cluster）和服务端点（endpoint）。Envoy初始化完成后，就根据这些配置信息对微服务间的通信进行寻址和路由。

## 命令行工具

kubectl和Istioctl，由于Istio的配置是基于K8S的CRD，因此可以直接采用kubectl对这些资源进行操作。Istioctl则针对Istio对CRD的操作进行了一些封装。Istioctl支持的功能参见该[表格](https://istio.io/docs/reference/commands/istioctl)。
