如果采用了Consul作为Service Registry，可以通过下面的接口查看Consul中的服务注册信息，以和Pilot及Envoy中的服务信息进行对比分析。

查看Consul中注册的所有服务
```bash
curl http://172.167.40.2:1107/v1/catalog/services
```

查看某一个服务的具体内容
```bash
curl http://172.167.40.2:1107/v1/catalog/service/{service}
```

参考： https://www.consul.io/api/catalog.html