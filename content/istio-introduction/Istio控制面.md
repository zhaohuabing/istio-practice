Istio控制面板包括3个组件:Pilot, Mixer和Istio-Auth。

#### Pilot
Pilot维护了网格中的服务的标准模型，这个标准模型是独立于各种底层平台的。Pilot通过适配器和各底层平台对接，以填充此标准模型。

例如Pilot中的Kubernetes适配器通过Kubernetes API服务器得到kubernetes中pod注册信息的更改，入口资源以及存储流量管理规则等信息，然后将该数据被翻译为标准模型提供给Pilot使用。通过适配器模式，Pilot还可以从Mesos, Cloud Foundry, Consul中获取服务信息，也可以开发适配器将其他提供服务发现的组件集成到Pilot中。

除此以外，Pilo还定义了一套和数据面通信的标准API，API提供的接口内容包括服务发现 、负载均衡池和路由表的动态更新。通过该标准API将控制面和数据面进行了解耦，简化了设计并提升了跨平台的可移植性。基于该标准API已经实现了多种Sidecar代理和Istio的集成，除Istio目前集成的Envoy外，还可以和Linkerd, Nginmesh等第三方通信代理进行集成，也可以基于该API自己编写Sidecar实现。

Pilot还定义了一套DSL（Domain Specific Language）语言，DSL语言提供了面向业务的高层抽象，可以被运维人员理解和使用。运维人员使用该DSL定义流量规则并下发到Pilot，这些规则被Pilot翻译成数据面的配置，再通过标准API分发到Envoy实例，可以在运行期对微服务的流量进行控制和调整。

![](http://img.zhaohuabing.com/in-post/2018-03-29-what-is-service-mesh-and-istio/pilot.png)

#### Mixer
在微服务应用中，通常需要部署一些基础的后端公共服务以用于支撑业务功能。这些基础设施包括策略类如访问控制，配额管理；以及遥测报告如APM，日志等。微服务应用和这些后端支撑系统之间一般是直接集成的，这导致了应用和基础设置之间的紧密耦合，如果因为运维原因需要对基础设置进行升级或者改动，则需要修改各个微服务的应用代码，反之亦然。

为了解决该问题，Mixer在应用程序代码和基础架构后端之间引入了一个通用中间层。该中间层解耦了应用和后端基础设施，应用程序代码不再将应用程序代码与特定后端集成在一起，而是与Mixer进行相当简单的集成，然后Mixer负责与后端系统连接。

Mixer主要提供了三个核心功能：
* 前提条件检查。允许服务在响应来自服务消费者的传入请求之前验证一些前提条件。前提条件可以包括服务使用者是否被正确认证，是否在服务的白名单上，是否通过ACL检查等等。
* 配额管理。 使服务能够在分配和释放多个维度上的配额，配额这一简单的资源管理工具可以在服务消费者对有限资源发生争用时，提供相对公平的（竞争手段）。Rate Limiting就是配额的一个例子。
* 遥测报告。使服务能够上报日志和监控。在未来，它还将启用针对服务运营商以及服务消费者的跟踪和计费流。


Mixer的架构如图所示:

![](http://img.zhaohuabing.com/in-post/2018-03-29-what-is-service-mesh-and-istio/mixer2.png)

首先，Sidecar会从每一次请求中收集相关信息，如请求的路径，时间，源IP，目地服务，tracing头，日志等，并请这些属性上报给Mixer。Mixer和后端服务之间是通过适配器进行连接的，Mixer将Sidecar上报的内容通过适配器发送给后端服务。

由于Sidecar只和Mixer进行对接，和后端服务之间并没有耦合，因此使用Mixer适配器机制可以接入不同的后端服务，而不需要修改应用的代码，例如通过不同的Mixer适配器，可以把Metrics收集到Prometheus或者InfluxDB，甚至可以在不停止应用服务的情况下动态切换后台服务。

其次，Sidecar在进行每次请求处理时会通过Mixer进行策略判断，并根据Mixer返回的结果决定是否继续处理该次调用。通过该方式，Mixer将策略决策移出应用层，使运维人员可以在运行期对策略进行配置，动态控制应用的行为，提高了策略控制的灵活性。例如可以配置每个微服务应用的访问白名单，不同客户端的Rate limiting，等等。

逻辑上微服务之间的每一次请求调用都会经过两次Mixer的处理：调用前进行策略判断，调用后进行遥测数据收集。Istio采用了一些机制来避免Mixer的处理影响Envoy的转发效率。

从上图可以看到，Istio在Envoy中增加了一个Mixer Filter，该Filter和控制面的Mixer组件进行通讯，完成策略控制和遥测数据收集功能。Mixer Filter中保存有策略判断所需的数据缓存，因此大部分策略判断在Envoy中就处理了，不需要发送请求到Mixer。另外Envoy收集到的遥测数据会先保存在Envoy的缓存中，每隔一段时间再通过批量的方式上报到Mixer。


#### Auth
Istio支持双向SSL认证（Mutual SSL Authentication）和基于角色的访问控制（RBAC），以提供端到端的安全解决方案。

##### 认证
Istio提供了一个内部的CA(证书机构),该CA为每个服务颁发证书，提供服务间访问的双向SSL身份认证，并进行通信加密，其架构如下图所示：

![](http://img.zhaohuabing.com/in-post/2018-03-29-what-is-service-mesh-and-istio/auth.png)

其工作机制如下：
部署时：

* CA监听Kubernetes API Server, 为集群中的每一个Service Account创建一对密钥和证书，并发送给Kubernetes API Server。注意这里不是为每个服务生成一个证书，而是为每个Service Account生成一个证书。Service Account和kubernetes中部署的服务可以是一对多的关系。Service Account被保存在证书的SAN(Subject Alternative Name)字段中。
* 当Pod创建时，Kubernetes根据该Pod关联的Service Account将密钥和证书以Kubernetes Secrets资源的方式加载为Pod的Volume，以供Envoy使用。
* Pilot生成数据面的配置，包括Envoy需使用的密钥和证书信息，以及哪个Service Account可以允许运行哪些服务，下发到Envoy。
>备注：如果是虚机环境，则采用一个Node Agent生成密钥，向Istio CA申请证书，然后将证书传递给Envoy。

运行时：

* 服务客户端的出站请求被Envoy接管。
* 客户端的Envoy和服务端的Envoy开始双向SSL握手。在握手阶段，客户端Envoy会验证服务端Envoy证书中的Service Account有没有权限运行该请求的服务，如没有权限，则认为服务端不可信，不能创建链接。
* 当加密TSL链接创建好后，请求数据被发送到服务端的Envoy，然后被Envoy通过一个本地的TCP链接发送到服务中。

##### 鉴权

Istio“基于角色的访问控制”（RBAC）提供了命名空间，服务，方法三个不同大小粒度的服务访问权限控制。其架构如下图所示：

![](http://img.zhaohuabing.com/in-post/2018-03-29-what-is-service-mesh-and-istio/authorization.png)

管理人员可以定制访问控制的安全策略，这些安全策略保存在Istio Config Store中。 Istio RBAC Engine从Config Store中获取安全策略，根据安全策略对客户端发起的请求进行判断，并返回鉴权结果（允许或者禁止）。

Istio RBAC Engine目前被实现为一个Mixer Adapter，因此其可以从Mixer传递过来的上下文中获取到访问请求者的身份（Subject）和操作请求（Action），并通过Mixer对访问请求进行策略控制，允许或者禁止某一次请求。

Istio Policy中包含两个基本概念：

* ServiceRole，定义一个角色，并为该角色指定对网格中服务的访问权限。指定角色访问权限时可以在命名空间，服务，方法的不同粒度进行设置。

* ServiceRoleBinding，将角色绑定到一个Subject，可以是一个用户，一组用户或者一个服务。