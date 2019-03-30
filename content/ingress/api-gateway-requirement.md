## 应用对API Gateway的需求

采用Gateway和VirtualService实现的Istio Ingress Gateway提供了网络入口处的基础通信功能，包括可靠的通信和灵活的路由规则。但对于一个服务化应用来说，网络入口除了基础的通讯功能之外，还有一些其他的应用层功能需求，例如：

* 第三方系统对API的访问控制
* 用户对系统的访问控制
* 修改请求/返回数据
* 服务API的生命周期管理
* 服务访问的SLA、限流及计费
* ….

![Kubernetes ingress, Istio gateway and API gateway的功能对比](https://zhaohuabing.com/img/2018-12-27-the-obstacles-to-put-istio-into-production/ingress-comparation.png)

API Gateway需求中很大一部分需要根据不同的应用系统进行定制，目前看来暂时不大可能被纳入K8s Ingress或者Istio Gateway的规范之中。为了满足这些需求，涌现出了各类不同的k8s Ingress Controller以及Istio Ingress Gateway实现，包括Ambassador ，Kong, Traefik,Solo等。

这些网关产品在实现在提供基础的K8s Ingress能力的同时，提供了强大的API Gateway功能，但由于缺少统一的标准，这些扩展实现之间相互之间并不兼容。而且遗憾的是，目前这些Ingress controller都还没有正式提供和Istio 控制面集成的能力。

>备注：
>
> * Ambassador将对Istio路由规则的支持纳入了Roadmap https://www.getambassador.io/user-guide/with-istio/
> * Istio声称支持Istio-Based Route Rule Discovery (尚处于实验阶段) https://gloo.solo.io/introduction/architecture/