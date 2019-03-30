# 如何为服务网格选择入口网关？

在Istio服务网格中，通过为每个Service部署一个sidecar代理，Istio接管了Service之间的请求流量。控制面可以对网格中的所有sidecar代理进行统一配置，实现了对网格内部流量的路由控制，从而可以实现灰度发布，流量镜像，故障注入等服务管控功能。但是，Istio并没有为入口网关提供一个较为完善的解决方案。

## K8s Ingress

在0.8版本以前，Istio缺省采用K8s Ingress来作为Service Mesh的流量入口。K8s Ingress统一了应用的流量入口，但存在两个问题：

* K8s Ingress是独立在Istio体系之外的，需要单独采用Ingress rule进行配置，导致系统入口和内部存在两套互相独立的路由规则配置，运维和管理较为复杂。
* K8s Ingress rule的功能较弱，不能在入口处实现和网格内部类似的路由规则，也不具备网格sidecar的其它能力，导致难以从整体上为应用系统实现灰度发布、分布式跟踪等服务管控功能。

![采用Kubernetes Ingress作为服务网格的流量入口](https://zhaohuabing.com/img/2019-03-29-how-to-choose-ingress-for-service-mesh/K8s-ingress-and-Istio.png)