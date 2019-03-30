# Pilot高层架构

Istio控制面中负责流量管理的组件为Pilot，Pilot的高层架构如下图所示：

![](https://zhaohuabing.com/img/2018-09-25-istio-traffic-management-impl-intro/pilot-architecture.png)  
<center>Pilot Architecture（来自[Isio官网文档](https://istio.io/docs/concepts/traffic-management/)<sup>[[1]](#ref01)</sup>)</center>

根据上图,Pilot主要实现了下述功能：

## 统一的服务模型

Pilot定义了网格中服务的标准模型，这个标准模型独立于各种底层平台。由于有了该标准模型，各个不同的平台可以通过适配器和Pilot对接，将自己特有的服务数据格式转换为标准格式，填充到Pilot的标准模型中。

例如Pilot中的Kubernetes适配器通过Kubernetes API服务器得到kubernetes中service和pod的相关信息，然后翻译为标准模型提供给Pilot使用。通过适配器模式，Pilot还可以从Mesos, Cloud Foundry, Consul等平台中获取服务信息，还可以开发适配器将其他提供服务发现的组件集成到Pilot中。

## 标准数据面 API

Pilo使用了一套起源于Envoy项目的[标准数据面API](https://github.com/envoyproxy/data-plane-api/blob/master/API_OVERVIEW.md)<sup>[[2]](#ref02)</sup>来将服务信息和流量规则下发到数据面的sidecar中。

通过采用该标准API，Istio将控制面和数据面进行了解耦，为多种数据面sidecar实现提供了可能性。事实上基于该标准API已经实现了多种Sidecar代理和Istio的集成，除Istio目前集成的Envoy外，还可以和Linkerd, Nginmesh等第三方通信代理进行集成，也可以基于该API自己编写Sidecar实现。

控制面和数据面解耦是Istio后来居上，风头超过Service mesh鼻祖Linkerd的一招妙棋。Istio站在了控制面的高度上，而Linkerd则成为了可选的一种sidecar实现，可谓降维打击的一个典型成功案例！

数据面标准API也有利于生态圈的建立，开源，商业的各种sidecar以后可能百花齐放，用户也可以根据自己的业务场景选择不同的sidecar和控制面集成，如高吞吐量的，低延迟的，高安全性的等等。有实力的大厂商可以根据该API定制自己的sidecar，例如蚂蚁金服开源的Golang版本的Sidecar MOSN(Modular Observable Smart Netstub)（SOFAMesh中Golang版本的Sidecar)；小厂商则可以考虑采用成熟的开源项目或者提供服务的商业sidecar实现。

备注：Istio和Envoy项目联合制定了Envoy V2 API,并采用该API作为Istio控制面和数据面流量管理的标准接口。

## 业务DSL语言

Pilot还定义了一套DSL（Domain Specific Language）语言，DSL语言提供了面向业务的高层抽象，可以被运维人员理解和使用。运维人员使用该DSL定义流量规则并下发到Pilot，这些规则被Pilot翻译成数据面的配置，再通过标准API分发到Envoy实例，可以在运行期对微服务的流量进行控制和调整。

Pilot的规则DSL是采用K8S API Server中的[Custom Resource (CRD)](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)<sup>[[3]](#ref03)</sup>实现的，因此和其他资源类型如Service  Pod Deployment的创建和使用方法类似，都可以用Kubectl进行创建。

通过运用不同的流量规则，可以对网格中微服务进行精细化的流量控制，如按版本分流，断路器，故障注入，灰度发布等。

