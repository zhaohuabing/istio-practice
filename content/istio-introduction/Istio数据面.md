Istio数据面以“边车”(sidecar)的方式和微服务一起部署，为微服务提供安全、快速、可靠的服务间通讯。由于Istio的控制面和数据面以标准接口进行交互，因此数据可以有多种实现，Istio缺省使用了Envoy代理的扩展版本。

Envoy是以C ++开发的高性能代理，用于调解服务网格中所有服务的所有入站和出站流量。Envoy的许多内置功能被Istio发扬光大，例如动态服务发现，负载均衡，TLS加密，HTTP/2 & gRPC代理，熔断器，路由规则，故障注入和遥测等。

Istio数据面支持的特性如下：

| Outbound特性 | Inbound特性 |
|--------|--------|
| Service authentication（服务认证）|Service authentication（服务认证）|
|Load Balancing（负载均衡）        |Authorization（鉴权）|
|Retry and circuit breaker（重试和断路器）|Rate limits（请求限流）|
|Fine-grained routing（细粒度的路由）|Load shedding（负载控制）|
|Telemetry（遥测）|Telemetry（遥测）|
|Request Tracing（分布式追踪）|Request Tracing（分布式追踪）|
|Fault Injection（故障注入）|Fault Injection（故障注入）|

>备注：Outbound特性是指服务请求侧的Sidecar提供的功能特性，而Inbound特性是指服务提供侧Sidecar提供的功能特性。一些特性如遥测和分布式跟踪需要两侧的Sidecar都提供支持；而另一些特性则只需要在一侧提供，例如鉴权只需要在服务提供侧提供，重试只需要在请求侧提供。