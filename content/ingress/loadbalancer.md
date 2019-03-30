## LoadBalancer

NodePort提供了一种从外部网络访问Kubernetes集群内部Service的方法，但该方法存在下面一些限制，导致这种方式主要适用于程序开发，不适合用于产品部署。

* Kubernetes cluster host的IP必须是一个well-known IP，即客户端必须知道该IP。但Cluster中的host是被作为资源池看待的，可以增加删除，每个host的IP一般也是动态分配的，因此并不能认为host IP对客户端而言是well-known IP。
* 客户端访问某一个固定的host IP的方式存在单点故障。假如一台host宕机了，kubernetes cluster会把应用 reload到另一节点上，但客户端就无法通过该host的nodeport访问应用了。
* 通过一个主机节点作为网络入口，在网络流量较大时存在性能瓶颈。

为了解决这些问题，Kubernetes提供了LoadBalancer。通过将Service定义为LoadBalancer类型，Kubernetes在主机节点的NodePort前提供了一个四层的负载均衡器。该四层负载均衡器负责将外部网络流量分发到后面的多个节点的NodePort端口上。

下图展示了Kubernetes如何通过LoadBalancer方式对外提供流量入口，图中LoadBalancer后面接入了两个主机节点上的NodePort，后端部署了三个Pod提供服务。根据集群的规模，可以在LoadBalancer后面可以接入更多的主机节点，以进行负荷分担。

![NodeBalancer](https://zhaohuabing.com/img/2019-03-29-how-to-choose-ingress-for-service-mesh/Load-Balancer.png)

> 备注：LoadBalancer类型需要云服务提供商的支持，Service中的定义只是在Kubernetes配置文件中提出了一个要求，即为该Service创建Load Balancer，至于如何创建则是由Google Cloud或Amazon Cloud等云服务商提供的，创建的Load Balancer的过程不在Kubernetes Cluster的管理范围中。
> 
> 目前WS, Azure, CloudStack, GCE 和 OpenStack 等主流的公有云和私有云提供商都可以为Kubernetes提供Load Balancer。一般来说，公有云提供商还会为Load Balancer提供一个External IP，以提供Internet接入。如果你的产品没有使用云提供商，而是自建Kubernetes Cluster，则需要自己提供LoadBalancer。