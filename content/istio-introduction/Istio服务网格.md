Istio是一个Service Mesh开源项目，是Google继Kubernetes之后的又一力作，主要参与的公司包括Google，IBM和Lyft。

凭借kubernetes良好的架构设计及其强大的扩展性，Google围绕kubernetes打造一个生态系统。Kubernetes用于微服务的编排（编排是英文Orchestration的直译，用大白话说就是描述一组微服务之间的关联关系，并负责微服务的部署、终止、升级、缩扩容等）。其向下用CNI(容器网络接口），CRI（容器运行时接口）标准接口可以对接不同的网络和容器运行时实现，提供微服务运行的基础设施。向上则用Istio提供了微服务治理功能。

由下图可见，Istio补充了Kubernetes生态圈的重要一环，是Google的微服务版图里一个里程碑式的扩张。

![](http://img.zhaohuabing.com/in-post/2018-03-29-what-is-service-mesh-and-istio/k8s-ecosystem.PNG)

Google借Istio的力量推动微服务治理的事实标准，对Google自身的产品Google Cloud有极其重大的意义。其他的云服务厂商，如Redhat，Pivotal，Nginx，Buoyant等看到大势所趋，也纷纷跟进，宣布自身产品和Istio进行集成，以避免自己被落下，丢失其中的市场机会。

可以预见不久的将来，对于云原生应用而言，采用kubernetes进行服务部署和集群管理，采用Istio处理服务通讯和治理，将成为微服务应用的标准配置。

Istio服务包括网格由数据面和控制面两部分。
* 数据面由一组智能代理（Envoy）组成，代理部署为边车，调解和控制微服务之间所有的网络通信。
* 控制面负责管理和配置代理来路由流量，以及在运行时执行策略。

![](http://img.zhaohuabing.com/in-post/2018-03-29-what-is-service-mesh-and-istio/istio-architecture.png)
