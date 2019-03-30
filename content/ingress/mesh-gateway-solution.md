## 采用API Gateway + Sidecar Proxy作为服务网格的流量入口

在目前难以找到一个同时具备API Gateway和Isito Ingress能力的网关的情况下，一个可行的方案是使用API Gateway和Sidecar Proxy一起为服务网格提供外部流量入口。

由于API Gateway已经具备七层网关的功能，Mesh Ingress中的Sidecar只需要提供VirtualService资源的路由能力，并不需要提供Gateway资源的网关能力，因此采用Sidecar Proxy即可。网络入口处的Sidecar Proxy和网格内部应用Pod中Sidecar Proxy的唯一一点区别是：该Sidecar只接管API Gateway向Mesh内部的流量，并不接管外部流向API Gateway的流量；而应用Pod中的Sidecar需要接管进入应用的所有流量。

![采用API Gateway + Sidecar Proxy为服务网格提供流量入口](https://zhaohuabing.com/img/2019-03-29-how-to-choose-ingress-for-service-mesh/API-Gateway-and-Sidecar-Proxy-as-Ingress-for-Istio.png)

> 备注：在实际部署时，API Gateway前端需要采用NodePort和LoadBalancer提供外部流量入口。为了突出主题，对上图进行了简化，没有画出NodePort和LoadBalancer。

采用API Gateway和Sidecar Proxy一起作为服务网格的流量入口，既能够通过对网关进行定制开发满足产品对API网关的各种需求，又可以在网络入口处利用服务网格提供的灵活的路由能力和分布式跟踪，策略等管控功能，是服务网格产品入口网关的一个理想方案。


性能方面的考虑：从上图可以看到，采用该方案后，外部请求的处理流程在入口处增加了Sidecar Proxy这一跳，因此该方式会带来少量的性能损失，但该损失是完全可以接受的。

对于请求时延而言，在服务网格中，一个外部请求本来就要经过较多的代理和应用进程的处理，在Ingress处增加一个代理对整体的时延影响基本忽略不计，而且对于绝大多数应用来说，网络转发所占的时间比例本来就很小，99%的耗时都在业务逻辑。如果系统对于增加的该时延非常敏感，则建议重新考虑该系统是否需要采用微服务架构和服务网格。

对于吞吐量而言，如果入口处的网络吞吐量存在瓶颈，则可以通过对API Gateway + Sidecar Proxy组成的Ingress整体进行水平扩展，来对入口流量进行负荷分担，以提高网格入口的网络吞吐量。

## 参考
本章节参考了下述链接中的文档。

- <a id="ref01">[Virtual IPs and Service Proxie - kubernetes.io](https://kubernetes.io/docs/concepts/services-networking/service/#virtual-ips-and-service-proxies)
- [如何从外部访问Kubernetes集群中的应用？ - zhaohuabing.com](https://zhaohuabing.com/2017/11/28/access-application-from-outside/)
- [The obstacles to put Istio into production and how we solve them - kubernetes.io](https://zhaohuabing.com/post/2018-12-27-the-obstacles-to-put-istio-into-production/#service-mesh-and-api-gateway)
- [Kubernetes NodePort vs LoadBalancer vs Ingress? When should I use what? - medium.com](https://medium.com/google-cloud/kubernetes-nodeport-vs-loadbalancer-vs-ingress-when-should-i-use-what-922f010849e0)