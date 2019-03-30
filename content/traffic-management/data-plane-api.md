# 数据面标准API
前面讲到，Pilot采用了一套标准的API来向数据面Sidecar提供服务发现，负载均衡池和路由表等流量管理的配置信息。该标准API的文档参见[Envoy v2 API](https://www.envoyproxy.io/docs/envoy/latest/configuration/overview/v2_overview)<sup>[[5]](#ref05)</sup>。[Data Plane API Protocol Buffer Definition](https://github.com/envoyproxy/data-plane-api/tree/master/envoy/api/v2)<sup>[[6]](#ref06)</sup>)给出了v2 grpc接口相关的数据结构和接口定义。

（备注：Istio早期采用了Envoy v1 API，目前的版本中则使用V2 API，V1已被废弃）。

## 基本概念和术语

首先我们需要了解数据面API中涉及到的一些基本概念：

* **Host**：能够进行网络通信的实体（如移动设备、服务器上的应用程序）。在此文档中，主机是逻辑网络应用程序。一块物理硬件上可能运行有多个主机，只要它们是可以独立寻址的。在EDS接口中，也使用“Endpoint”来表示一个应用实例，对应一个IP+Port的组合。
* **Downstream**：下游主机连接到 Envoy，发送请求并接收响应。
* **Upstream**：上游主机接收来自 Envoy 的连接和请求，并返回响应。
* **Listener**：监听器是命名网地址（例如，端口、unix domain socket等)，可以被下游客户端连接。Envoy 暴露一个或者多个监听器给下游主机连接。在Envoy中,Listener可以绑定到端口上直接对外服务，也可以不绑定到端口上，而是接收其他listener转发的请求。
* **Cluster**：集群是指 Envoy 连接到的逻辑上相同的一组上游主机。Envoy 通过服务发现来发现集群的成员。可以选择通过主动健康检查来确定集群成员的健康状态。Envoy 通过负载均衡策略决定将请求路由到哪个集群成员。

## XDS服务接口
 Istio数据面API定义了xDS服务接口，Pilot通过该接口向数据面sidecar下发动态配置信息，以对Mesh中的数据流量进行控制。xDS中的DS表示discovery service，即发现服务，表示xDS接口使用动态发现的方式提供数据面所需的配置数据。而x则是一个代词，表示有多种discover service。这些发现服务及对应的数据结构如下：

* LDS (Listener Discovery Service)  [envoy.api.v2.Listener](https://github.com/envoyproxy/data-plane-api/blob/master/envoy/api/v2/lds.proto)
* CDS (Cluster Discovery Service)   [envoy.api.v2.RouteConfiguration](https://github.com/envoyproxy/data-plane-api/blob/master/envoy/api/v2/rds.proto)
* EDS (Endpoint Discovery Service)  [envoy.api.v2.Cluster](https://github.com/envoyproxy/data-plane-api/blob/master/envoy/api/v2/cds.proto)
* RDS (Route Discovery Service)     [envoy.api.v2.ClusterLoadAssignment](https://github.com/envoyproxy/data-plane-api/blob/master/envoy/api/v2/eds.proto)

## XDS服务接口的最终一致性考虑

xDS的几个接口是相互独立的，接口下发的配置数据是最终一致的。但在配置更新过程中，可能暂时出现各个接口的数据不匹配的情况，从而导致部分流量在更新过程中丢失。

设想这种场景：在CDS/EDS只知道cluster X的情况下,RDS的一条路由配置将指向Cluster X的流量调整到了Cluster Y。在CDS/EDS向Mesh中Envoy提供Cluster Y的更新前，这部分导向Cluster Y的流量将会因为Envoy不知道Cluster Y的信息而被丢弃。

对于某些应用来说，短暂的部分流量丢失是可以接受的，例如客户端重试可以解决该问题，并不影响业务逻辑。对于另一些场景来说，这种情况可能无法容忍。可以通过调整xDS接口的更新逻辑来避免该问题，对上面的情况，可以先通过CDS/EDS更新Y Cluster，然后再通过RDS将X的流量路由到Y。

一般来说，为了避免Envoy配置数据更新过程中出现流量丢失的情况，xDS接口应采用下面的顺序：

1. CDS 首先更新Cluster数据（如果有变化）
1. EDS 更新相应Cluster的Endpoint信息（如果有变化）
1. LDS 更新CDS/EDS相应的Listener。
1. RDS 最后更新新增Listener相关的Route配置。
1. 删除不再使用的CDS cluster和 EDS endpoints。

## ADS聚合发现服务

保证控制面下发数据一致性，避免流量在配置更新过程中丢失的另一个方式是使用ADS(Aggregated Discovery Services)，即聚合的发现服务。ADS通过一个gRPC流来发布所有的配置更新，以保证各个xDS接口的调用顺序，避免由于xDS接口更新顺序导致的配置数据不一致问题。

关于XDS接口的详细介绍可参考[xDS REST and gRPC protocol](https://github.com/envoyproxy/data-plane-api/blob/master/XDS_PROTOCOL.md)<sup>[[7]](#ref07)</sup>

