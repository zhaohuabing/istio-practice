Pilot提供了一个调试端口9093，可以通过向调试端口发送REST请求来分析和查看标准数据面接口(Envoy xDS API)的数据和Pilot内部存储的状态信息。

#### xDS接口相关调试信息

发送给Enovy的Listener，Filter及Route配置
```bash
curl http://127.0.0.1:9093/debug/adsz
```

各个Cluster中配置的Endpoint
```bash
curl http://127.0.0.1:9093/debug/edsz
```

Cluster信息
```bash
curl http://127.0.0.1:9093/debug/cdsz
```

备注：上述接口中的配置信息在Envoy第一次连接到Pilot中时才会生成，在此之前，通过接口无法获取到数据。

#### Pilot内部的配置信息

服务注册表信息
```bash
curl http://127.0.0.1:9093/debug/registryz 
```

所有的endpoint
```bash
curl http://127.0.0.1:9093/debug/endpointz[?brief=1]
```

所有的配置信息
```bash
curl http://127.0.0.1:9093/debug/configz
```


Pilot自身的一些性能数据
```bash
curl http://127.0.0.1:9093/metrics
```

参考：https://github.com/istio/istio/tree/master/pilot/pkg/proxy/envoy/v2
