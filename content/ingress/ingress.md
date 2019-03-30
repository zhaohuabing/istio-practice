## Ingress

LoadBalancer类型的Service提供的是四层负载均衡器，当只需要向外暴露一个服务的时候，采用这种方式是没有问题的。但当一个应用需要对外提供多个服务时，采用该方式则要求为每一个四层服务（IP+Port）都创建一个外部load balancer。

一般来说，同一个应用的多个服务/资源会放在同一个域名下，在这种情况下，创建多个Load balancer是完全没有必要的，反而带来了额外的开销和管理成本。另外直接将服务暴露给外部用户也会导致了前端和后端的耦合，影响了后端架构的灵活性，如果以后由于业务需求对服务进行调整会直接影响到客户端。为了解决该问题，可以通过使用Kubernetes Ingress来作为网络入口。

### Ingress 功能介绍
Kubernetes Ingress声明了一个应用层（OSI七层）的负载均衡器，可以根据HTTP请求的内容将来自同一个TCP端口的请求分发到不同的Kubernetes Service，其功能包括：

* **按HTTP请求的URL进行路由** <BR>
同一个TCP端口进来的流量可以根据URL路由到Cluster中的不同服务，如下图所示：

![Simple fanout](https://zhaohuabing.com/img/2019-03-29-how-to-choose-ingress-for-service-mesh/Ingress-url-fanout.png)

* **按HTTP请求的Host进行路由** <BR>
同一个IP进来的流量可以根据HTTP请求的Host路由到Cluster中的不同服务，如下图所示：

![Name based virtual hosting](https://zhaohuabing.com/img/2019-03-29-how-to-choose-ingress-for-service-mesh/Ingress-name-based-route.png)

Ingress 规则定义了对七层网关的要求，包括URL分发规则，基于不同域名的虚拟主机，SSL证书等。Kubernetes使用Ingress Controller 来监控Ingress规则，并通过一个七层网关来实现这些要求，一般可以使用Nginx，HAProxy，Envoy等。

### Ingress配合NodePort和LoadBalancer提供对外流量入口

虽然Ingress Controller通过七层网关为后端的多个Service提供了统一的入口，但由于其部署在集群中，因此并不能直接对外提供服务。实际上Ingress需要配合NodePort和LoadBalancer才能提供对外的流量入口，如下图所示：

![采用Ingress, NodePortal和LoadBalancer提供外部流量入口的拓扑结构](https://zhaohuabing.com/img/2019-03-29-how-to-choose-ingress-for-service-mesh/Ingress+Nodeport+LoadBalancer-Topo.png)

上图描述了如何采用Ingress配合NodePort和Load Balancer为集群提供外部流量入口，从该拓扑图中可以看到该架构的伸缩性非常好，在NodePort，Ingress，Pod等不同的接入层面都可以对系统进行水平扩展，以应对不同的外部流量要求。

上图只展示了逻辑架构，下面的图展示了具体的实现原理：

![采用Ingress, NodePortal和LoadBalancer提供外部流量入口的实现原理](https://zhaohuabing.com/img/2019-03-29-how-to-choose-ingress-for-service-mesh/Ingress+NodePort+LoadBalancer-deep-dive.png)

流量从外部网络到达Pod的完整路径如下：

1. 外部请求先通过四层Load Balancer进入内部网络
1. Load Balancer将流量分发到后端多个主机节点上的NodePort (userspace转发)
1. 请求从NodePort进入到Ingress Controller (iptabes规则，Ingress Controller本身是一个NodePort类型的Service)
1. Ingress Controller根据Ingress rule进行七层分发，根据HTTP的URL和Host将请求分发给不同的Service (userspace转发)
1. Service将请求最终导入到后端提供服务的Pod中 (iptabes规则)

从前面的介绍可以看到，K8S Ingress提供了一个基础的七层网关功能的抽象定义，其作用是对外提供一个七层服务的统一入口，并根据URL/HOST将请求路由到集群内部不同的服务上。
