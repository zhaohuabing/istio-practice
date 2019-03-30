# Bookinfo 示例程序分析

下面我们以Bookinfo为例对Istio中的流量管理实现机制，以及控制面和数据面的交互进行进一步分析。

## Bookinfo程序结构

下图显示了Bookinfo示例程序中各个组件的IP地址，端口和调用关系，以用于后续的分析。

![](https://zhaohuabing.com/img/2018-09-25-istio-traffic-management-impl-intro/bookinfo.png)

## xDS接口调试方法

首先我们看看如何对xDS接口的相关数据进行查看和分析。Envoy v2接口采用了gRPC，由于gRPC是基于二进制的RPC协议，无法像V1的REST接口一样通过curl和浏览器进行进行分析。但我们还是可以通过Pilot和Envoy的调试接口查看xDS接口的相关数据。

### Pilot调试方法

Pilot在9093端口提供了下述[调试接口](https://github.com/istio/istio/tree/master/pilot/pkg/proxy/envoy/v2)<sup>[[8]](#ref08)</sup>下述方法查看xDS接口相关数据。

```
PILOT=istio-pilot.istio-system:9093

# What is sent to envoy
# Listeners and routes
curl $PILOT/debug/adsz

# Endpoints
curl $PILOT/debug/edsz

# Clusters
curl $PILOT/debug/cdsz
```

### Envoy调试方法

Envoy提供了管理接口，缺省为localhost的15000端口，可以获取listener，cluster以及完整的配置数据导出功能。

```
kubectl exec productpage-v1-54b8b9f55-bx2dq -c istio-proxy curl http://127.0.0.1:15000/help
  /: Admin home page
  /certs: print certs on machine
  /clusters: upstream cluster status
  /config_dump: dump current Envoy configs (experimental)
  /cpuprofiler: enable/disable the CPU profiler
  /healthcheck/fail: cause the server to fail health checks
  /healthcheck/ok: cause the server to pass health checks
  /help: print out list of admin commands
  /hot_restart_version: print the hot restart compatibility version
  /listeners: print listener addresses
  /logging: query/change logging levels
  /quitquitquit: exit the server
  /reset_counters: reset all counters to zero
  /runtime: print runtime values
  /runtime_modify: modify runtime values
  /server_info: print server version/status information
  /stats: print server stats
  /stats/prometheus: print server stats in prometheus format
```

进入productpage pod 中的istio-proxy(Envoy) container，可以看到有下面的监听端口

* 9080: productpage进程对外提供的服务端口
* 15001: Envoy的入口监听器，iptable会将pod的流量导入该端口中由Envoy进行处理
* 15000: Envoy管理端口，该端口绑定在本地环回地址上，只能在Pod内访问。

```
kubectl exec t productpage-v1-54b8b9f55-bx2dq -c istio-proxy --  netstat -ln
 
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 0.0.0.0:9080            0.0.0.0:*               LISTEN      -               
tcp        0      0 127.0.0.1:15000         0.0.0.0:*               LISTEN      13/envoy        
tcp        0      0 0.0.0.0:15001           0.0.0.0:*               LISTEN      13/envoy  
``` 
 
## Envoy启动过程分析

Istio通过K8s的[Admission webhook](https://zhaohuabing.com/2018/05/23/istio-auto-injection-with-webhook)<sup>[[9]](#ref09)</sup>机制实现了sidecar的自动注入，Mesh中的每个微服务会被加入Envoy相关的容器。下面是Productpage微服务的Pod内容，可见除productpage之外，Istio还在该Pod中注入了两个容器gcr.io/istio-release/proxy_init和gcr.io/istio-release/proxyv2。

备注：下面Pod description中只保留了需要关注的内容，删除了其它不重要的部分。为方便查看，本文中后续的其它配置文件以及命令行输出也会进行类似处理。

```
ubuntu@envoy-test:~$ kubectl describe pod productpage-v1-54b8b9f55-bx2dq

Name:               productpage-v1-54b8b9f55-bx2dq
Namespace:          default
Init Containers:
  istio-init:
    Image:         gcr.io/istio-release/proxy_init:1.0.0
      Args:
      -p
      15001
      -u
      1337
      -m
      REDIRECT
      -i
      *
      -x

      -b
      9080,
      -d

Containers:
  productpage:
    Image:          istio/examples-bookinfo-productpage-v1:1.8.0
    Port:           9080/TCP
    
  istio-proxy:
    Image:         gcr.io/istio-release/proxyv2:1.0.0
    Args:
      proxy
      sidecar
      --configPath
      /etc/istio/proxy
      --binaryPath
      /usr/local/bin/envoy
      --serviceCluster
      productpage
      --drainDuration
      45s
      --parentShutdownDuration
      1m0s
      --discoveryAddress
      istio-pilot.istio-system:15007
      --discoveryRefreshDelay
      1s
      --zipkinAddress
      zipkin.istio-system:9411
      --connectTimeout
      10s
      --statsdUdpAddress
      istio-statsd-prom-bridge.istio-system:9125
      --proxyAdminPort
      15000
      --controlPlaneAuthPolicy
      NONE
```

### Proxy_init

Productpage的Pod中有一个InitContainer proxy_init，InitContrainer是K8S提供的机制，用于在Pod中执行一些初始化任务.在Initialcontainer执行完毕并退出后，才会启动Pod中的其它container。

我们看一下proxy_init容器中的内容：


```
ubuntu@envoy-test:~$ sudo docker inspect gcr.io/istio-release/proxy_init:1.0.0
[
    {
        "RepoTags": [
            "gcr.io/istio-release/proxy_init:1.0.0"
        ],

        "ContainerConfig": {
            "Env": [
                "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
            ],
            "Cmd": [
                "/bin/sh",
                "-c",
                "#(nop) ",
                "ENTRYPOINT [\"/usr/local/bin/istio-iptables.sh\"]"
            ],
            "Entrypoint": [
                "/usr/local/bin/istio-iptables.sh"
            ],
        },
    }
]
```

从上面的命令行输出可以看到，Proxy_init中执行的命令是istio-iptables.sh，该脚本源码较长，就不列出来了，有兴趣可以在Istio 源码仓库的[tools/deb/istio-iptables.sh](https://github.com/istio/istio/blob/master/tools/deb/istio-iptables.sh)查看。

该脚本的作用是通过配置iptable来劫持Pod中的流量。结合前面Pod中该容器的命令行参数-p 15001，可以得知Pod中的数据流量被iptable拦截，并发向Envoy的15001端口。  -u 1337参数用于排除用户ID为1337，即Envoy自身的流量，以避免Iptable把Envoy发出的数据又重定向到Envoy，形成死循环。

### Proxyv2

前面提到，该容器中有两个进程Pilot-agent和envoy。我们进入容器中看看这两个进程的相关信息。

```
ubuntu@envoy-test:~$ kubectl exec   productpage-v1-54b8b9f55-bx2dq -c istio-proxy -- ps -ef

UID        PID  PPID  C STIME TTY          TIME CMD
istio-p+     1     0  0 Sep06 ?        00:00:00 /usr/local/bin/pilot-agent proxy sidecar --configPath /etc/istio/proxy --binaryPath /usr/local/bin/envoy --serviceCluster productpage --drainDuration 45s --parentShutdownDuration 1m0s --discoveryAddress istio-pilot.istio-system:15007 --discoveryRefreshDelay 1s --zipkinAddress zipkin.istio-system:9411 --connectTimeout 10s --statsdUdpAddress istio-statsd-prom-bridge.istio-system:9125 --proxyAdminPort 15000 --controlPlaneAuthPolicy NONE
istio-p+    13     1  0 Sep06 ?        00:47:37 /usr/local/bin/envoy -c /etc/istio/proxy/envoy-rev0.json --restart-epoch 0 --drain-time-s 45 --parent-shutdown-time-s 60 --service-cluster productpage --service-node sidecar~192.168.206.23~productpage-v1-54b8b9f55-bx2dq.default~default.svc.cluster.local --max-obj-name-len 189 -l warn --v2-config-only
```

Envoy的大部分配置都是dynamic resource，包括网格中服务相关的service cluster, listener, route规则等。这些dynamic resource是通过xDS接口从Istio控制面中动态获取的。但Envoy如何知道xDS server的地址呢？这是在Envoy初始化配置文件中以static resource的方式配置的。


#### Envoy初始配置文件
Pilot-agent进程根据启动参数和K8S API Server中的配置信息生成Envoy的初始配置文件，并负责启动Envoy进程。从ps命令输出可以看到Pilot-agent在启动Envoy进程时传入了pilot地址和zipkin地址，并为Envoy生成了一个初始化配置文件envoy-rev0.json

Pilot agent生成初始化配置文件的代码：
https://github.com/istio/istio/blob/release-1.0/pkg/bootstrap/bootstrap_config.go 137行

```
// WriteBootstrap generates an envoy config based on config and epoch, and returns the filename.
// TODO: in v2 some of the LDS ports (port, http_port) should be configured in the bootstrap.
func WriteBootstrap(config *meshconfig.ProxyConfig, node string, epoch int, pilotSAN []string, opts map[string]interface{}) (string, error) {
	if opts == nil {
		opts = map[string]interface{}{}
	}
	if err := os.MkdirAll(config.ConfigPath, 0700); err != nil {
		return "", err
	}
	// attempt to write file
	fname := configFile(config.ConfigPath, epoch)

	cfg := config.CustomConfigFile
	if cfg == "" {
		cfg = config.ProxyBootstrapTemplatePath
	}
	if cfg == "" {
		cfg = DefaultCfgDir
	}
	......

	if config.StatsdUdpAddress != "" {
		h, p, err = GetHostPort("statsd UDP", config.StatsdUdpAddress)
		if err != nil {
			return "", err
		}
		StoreHostPort(h, p, "statsd", opts)
	}

	fout, err := os.Create(fname)
	if err != nil {
		return "", err
	}

	// Execute needs some sort of io.Writer
	err = t.Execute(fout, opts)
	return fname, err
}
```

可以使用下面的命令将productpage pod中该文件导出来查看其中的内容：

```
kubectl exec productpage-v1-54b8b9f55-bx2dq -c istio-proxy -- cat /etc/istio/proxy/envoy-rev0.json > envoy-rev0.json
```

配置文件的结构如图所示：

![](https://zhaohuabing.com/img/2018-09-25-istio-traffic-management-impl-intro/envoy-rev0.png)  

其中各个配置节点的内容如下：

##### Node

包含了Envoy所在节点相关信息。

```
"node": {
    "id": "sidecar~192.168.206.23~productpage-v1-54b8b9f55-bx2dq.default~default.svc.cluster.local",
    //用于标识envoy所代理的node（在k8s中对应为Pod）上的service cluster，来自于Envoy进程启动时的service-cluster参数
    "cluster": "productpage",  
    "metadata": {
          "INTERCEPTION_MODE": "REDIRECT",
          "ISTIO_PROXY_SHA": "istio-proxy:6166ae7ebac7f630206b2fe4e6767516bf198313",
          "ISTIO_PROXY_VERSION": "1.0.0",
          "ISTIO_VERSION": "1.0.0",
          "POD_NAME": "productpage-v1-54b8b9f55-bx2dq",
          "istio": "sidecar"
    }
  }
```

##### Admin

配置Envoy的日志路径以及管理端口。

```
"admin": {
    "access_log_path": "/dev/stdout",
    "address": {
      "socket_address": {
        "address": "127.0.0.1",
        "port_value": 15000
      }
    }
  }
```

##### Dynamic_resources

配置动态资源,这里配置了ADS服务器。

```
"dynamic_resources": {
    "lds_config": {
        "ads": {}
    },
    "cds_config": {
        "ads": {}
    },
    "ads_config": {
      "api_type": "GRPC",
      "refresh_delay": {"seconds": 1, "nanos": 0},
      "grpc_services": [
        {
          "envoy_grpc": {
            "cluster_name": "xds-grpc"
          }
        }
      ]
    }
  }```
```

##### Static_resources

配置静态资源，包括了xds-grpc和zipkin两个cluster。其中xds-grpc cluster对应前面dynamic_resources中ADS配置，指明了Envoy用于获取动态资源的服务器地址。

```
"static_resources": {
    "clusters": [
    {
    "name": "xds-grpc",
    "type": "STRICT_DNS",
    "connect_timeout": {"seconds": 10, "nanos": 0},
    "lb_policy": "ROUND_ROBIN",

    "hosts": [
    {
    "socket_address": {"address": "istio-pilot.istio-system", "port_value": 15010}
    }
    ],
    "circuit_breakers": {
        "thresholds": [
      {
        "priority": "default",
        "max_connections": "100000",
        "max_pending_requests": "100000",
        "max_requests": "100000"
      },
      {
        "priority": "high",
        "max_connections": "100000",
        "max_pending_requests": "100000",
        "max_requests": "100000"
      }]
    },
    "upstream_connection_options": {
      "tcp_keepalive": {
        "keepalive_time": 300
      }
    },
    "http2_protocol_options": { }
    } ,
      {
        "name": "zipkin",
        "type": "STRICT_DNS",
        "connect_timeout": {
          "seconds": 1
        },
        "lb_policy": "ROUND_ROBIN",
        "hosts": [
          {
            "socket_address": {"address": "zipkin.istio-system", "port_value": 9411}
          }
        ]
      }
      
    ]
  }
```

##### Tracing

配置分布式链路跟踪。

```
"tracing": {
    "http": {
      "name": "envoy.zipkin",
      "config": {
        "collector_cluster": "zipkin"
      }
    }
  }
```

##### Stats_sinks

这里配置的是和Envoy直连的metrics收集sink,和Mixer telemetry没有关系。Envoy自带stats格式的metrics上报。

```
"stats_sinks": [
    {
      "name": "envoy.statsd",
      "config": {
        "address": {
          "socket_address": {"address": "10.103.219.158", "port_value": 9125}
        }
      }
    }
  ]
```
在Gist https://gist.github.com/zhaohuabing/14191bdcf72e37bf700129561c3b41ae中可以查看该配置文件的完整内容。

## Envoy配置分析

### 通过管理接口获取完整配置

从Envoy初始化配置文件中，我们可以大致看到Istio通过Envoy来实现服务发现和流量管理的基本原理。即控制面将xDS server信息通过static resource的方式配置到Envoy的初始化配置文件中，Envoy启动后通过xDS server获取到dynamic resource，包括网格中的service信息及路由规则。

Envoy配置初始化流程：

![](https://zhaohuabing.com/img/2018-09-25-istio-traffic-management-impl-intro/envoy-config-init.png)  

1. Pilot-agent根据启动参数和K8S API Server中的配置信息生成Envoy的初始配置文件envoy-rev0.json，该文件告诉Envoy从xDS server中获取动态配置信息，并配置了xDS server的地址信息，即控制面的Pilot。
1. Pilot-agent使用envoy-rev0.json启动Envoy进程。
1. Envoy根据初始配置获得Pilot地址，采用xDS接口从Pilot获取到Listener，Cluster，Route等d动态配置信息。
1. Envoy根据获取到的动态配置启动Listener，并根据Listener的配置，结合Route和Cluster对拦截到的流量进行处理。

可以看到，Envoy中实际生效的配置是由初始化配置文件中的静态配置和从Pilot获取的动态配置一起组成的。因此只对envoy-rev0
.json进行分析并不能看到Mesh中流量管理的全貌。那么有没有办法可以看到Envoy中实际生效的完整配置呢？答案是可以的，我们可以通过Envoy的管理接口来获取Envoy的完整配置。

```
kubectl exec -it productpage-v1-54b8b9f55-bx2dq -c istio-proxy curl http://127.0.0.1:15000/config_dump > config_dump
```
该文件内容长达近7000行，本文中就不贴出来了，在Gist https://gist.github.com/zhaohuabing/034ef87786d290a4e89cd6f5ad6fcc97 中可以查看到全文。

### Envoy配置文件结构

![](https://zhaohuabing.com/img/2018-09-25-istio-traffic-management-impl-intro/envoy-config.png)  

文件中的配置节点包括：

#### Bootstrap

从名字可以大致猜出这是Envoy的初始化配置，打开该节点，可以看到文件中的内容和前一章节中介绍的envoy-rev0.json是一致的，这里不再赘述。

![](https://zhaohuabing.com/img/2018-09-25-istio-traffic-management-impl-intro/envoy-config-bootstrap.png)  

#### Clusters 

在Envoy中，Cluster是一个服务集群，Cluster中包含一个到多个endpoint，每个endpoint都可以提供服务，Envoy根据负载均衡算法将请求发送到这些endpoint中。

在Productpage的clusters配置中包含static_clusters和dynamic_active_clusters两部分，其中static_clusters是来自于envoy-rev0.json的xDS server和zipkin server信息。dynamic_active_clusters是通过xDS接口从Istio控制面获取的动态服务信息。

![](https://zhaohuabing.com/img/2018-09-25-istio-traffic-management-impl-intro/envoy-config-clusters.png)  

Dynamic Cluster中有以下几类Cluster：

##### Outbound Cluster

这部分的Cluster占了绝大多数，该类Cluster对应于Envoy所在节点的外部服务。以details为例，对于Productpage来说,details是一个外部服务，因此其Cluster名称中包含outbound字样。

从details 服务对应的cluster配置中可以看到，其类型为EDS，即表示该Cluster的endpoint来自于动态发现，动态发现中eds_config则指向了ads，最终指向static Resource中配置的xds-grpc cluster,即Pilot的地址。

```
{
 "version_info": "2018-09-06T09:34:19Z",
 "cluster": {
  "name": "outbound|9080||details.default.svc.cluster.local",
  "type": "EDS",
  "eds_cluster_config": {
   "eds_config": {
    "ads": {}
   },
   "service_name": "outbound|9080||details.default.svc.cluster.local"
  },
  "connect_timeout": "1s",
  "circuit_breakers": {
   "thresholds": [
    {}
   ]
  }
 },
 "last_updated": "2018-09-06T09:34:20.404Z"
}
```

可以通过Pilot的调试接口获取该Cluster的endpoint：

```
curl http://10.96.8.103:9093/debug/edsz > pilot_eds_dump
```

导出的文件长达1300多行，本文只贴出details服务相关的endpoint配置，完整文件参见:https://gist.github.com/zhaohuabing/a161d2f64746acd18097b74e6a5af551

从下面的文件内容可以看到，details cluster配置了1个endpoint地址，是details的pod ip。
```
{
  "clusterName": "outbound|9080||details.default.svc.cluster.local",
  "endpoints": [
    {
      "locality": {

      },
      "lbEndpoints": [
        {
          "endpoint": {
            "address": {
              "socketAddress": {
                "address": "192.168.206.21",
                "portValue": 9080
              }
            }
          },
          "metadata": {
            "filterMetadata": {
              "istio": {
                  "uid": "kubernetes://details-v1-6764bbc7f7-qwzdg.default"
                }
            }
          }
        }
      ]
    }
  ]
}
```

##### Inbound Cluster

该类Cluster对应于Envoy所在节点上的服务。如果该服务接收到请求，当然就是一个入站请求。对于Productpage Pod上的Envoy，其对应的Inbound Cluster只有一个，即productpage。该cluster对应的host为127.0.0.1,即环回地址上productpage的监听端口。由于iptable规则中排除了127.0.0.1,入站请求通过该Inbound cluster处理后将跳过Envoy，直接发送给Productpage进程处理。

```
{
   "version_info": "2018-09-14T01:44:05Z",
   "cluster": {
    "name": "inbound|9080||productpage.default.svc.cluster.local",
    "connect_timeout": "1s",
    "hosts": [
     {
      "socket_address": {
       "address": "127.0.0.1",
       "port_value": 9080
      }
     }
    ],
    "circuit_breakers": {
     "thresholds": [
      {}
     ]
    }
   },
   "last_updated": "2018-09-14T01:44:05.291Z"
}
```

##### BlackHoleCluster

这是一个特殊的Cluster，并没有配置后端处理请求的Host。如其名字所暗示的一样，请求进入后将被直接丢弃掉。如果一个请求没有找到其对的目的服务，则被发到cluste。

```
{
   "version_info": "2018-09-06T09:34:19Z",
   "cluster": {
    "name": "BlackHoleCluster",
    "connect_timeout": "5s"
   },
   "last_updated": "2018-09-06T09:34:20.408Z"
}

```

#### Listeners

Envoy采用listener来接收并处理downstream发过来的请求，listener的处理逻辑是插件式的，可以通过配置不同的filter来插入不同的处理逻辑。Istio就在Envoy中加入了用于policy check和metric report的Mixer filter。

Listener可以绑定到IP Socket或者Unix Domain Socket上，也可以不绑定到一个具体的端口上，而是接收从其他listener转发来的数据。Istio就是利用了Envoy listener的这一特点实现了将来发向不同服务的请求转交给不同的listener处理。


##### Virtual Listener 

Envoy创建了一个在15001端口监听的入口监听器。Iptable将请求截取后发向15001端口，该监听器接收后并不进行业务处理，而是根据请求目的地分发给其他监听器处理。该监听器取名为"virtual"（虚拟）监听器也是这个原因。

Envoy是如何做到按服务分发的呢？ 可以看到该Listener的配置项use_original_dest设置为true,该配置要求监听器将接收到的请求转交给和请求原目的地址关联的listener进行处理。 

从其filter配置可以看到，如果找不到和请求目的地配置的listener进行转交，则请求将被发送到[BlackHoleCluster](#blackholecluster),由于BlackHoleCluster并没有配置host，因此找不到对应目的地对应监听器的请求实际上会被丢弃。

```
    {
     "version_info": "2018-09-06T09:34:19Z",
     "listener": {
      "name": "virtual",
      "address": {
       "socket_address": {
        "address": "0.0.0.0",
        "port_value": 15001
       }
      },
      "filter_chains": [
       {
        "filters": [
         {
          "name": "envoy.tcp_proxy",
          "config": {
           "stat_prefix": "BlackHoleCluster",
           "cluster": "BlackHoleCluster"
          }
         }
        ]
       }
      ],
      "use_original_dst": true
     },
     "last_updated": "2018-09-06T09:34:26.262Z"
    }
```

##### Inbound Listener

在Productpage Pod上的Envoy创建了Listener 192.168.206.23_9080，当外部调用Productpage服务的请求到达Pod上15001的"Virtual" Listener时，Virtual Listener根据请求目的地匹配到该Listener,请求将被转发过来。

```
    {
     "version_info": "2018-09-14T01:44:05Z",
     "listener": {
      "name": "192.168.206.23_9080",
      "address": {
       "socket_address": {
        "address": "192.168.206.23",
        "port_value": 9080
       }
      },
      "filter_chains": [
       {
        "filters": [
         {
          "name": "mixer",
          "config": {
           "transport": {
            "check_cluster": "outbound|9091||istio-policy.istio-system.svc.cluster.local",
            "network_fail_policy": {
             "policy": "FAIL_CLOSE"
            },
            "report_cluster": "outbound|9091||istio-telemetry.istio-system.svc.cluster.local",
            "attributes_for_mixer_proxy": {
             "attributes": {
              "source.uid": {
               "string_value": "kubernetes://productpage-v1-54b8b9f55-bx2dq.default"
              }
             }
            }
           },
           "mixer_attributes": {
            "attributes": {
             "destination.port": {
              "int64_value": "9080"
             },
             "context.reporter.uid": {
              "string_value": "kubernetes://productpage-v1-54b8b9f55-bx2dq.default"
             },
             "destination.namespace": {
              "string_value": "default"
             },
             "destination.ip": {
              "bytes_value": "AAAAAAAAAAAAAP//wKjOFw=="
             },
             "destination.uid": {
              "string_value": "kubernetes://productpage-v1-54b8b9f55-bx2dq.default"
             },
             "context.reporter.kind": {
              "string_value": "inbound"
             }
            }
           }
          }
         },
         {
          "name": "envoy.tcp_proxy",
          "config": {
           "stat_prefix": "inbound|9080||productpage.default.svc.cluster.local",
           "cluster": "inbound|9080||productpage.default.svc.cluster.local"
          }
         }
        ]
       }
      ],
      "deprecated_v1": {
       "bind_to_port": false
      }
     },
     "last_updated": "2018-09-14T01:44:05.754Z"
    }
```

从上面的配置"bind_to_port": false可以得知该listener创建后并不会被绑定到tcp端口上直接接收网络上的数据，因此其所有请求都转发自15001端口。

该listener配置的envoy.tcp_proxy filter对应的cluster为["inbound|9080||productpage.default.svc.cluster.local"](#inbound-cluster),该cluster配置的host为127.0.0.1:9080，因此Envoy会将该请求发向127.0.0.1:9080。由于iptable设置中127.0.0.1不会被拦截,该请求将发送到Productpage进程的9080端口进行业务处理。

除此以外，Listenter中还包含Mixer filter的配置信息，配置了策略检查(Mixer check)和Metrics上报(Mixer report)服务器地址，以及Mixer上报的一些attribute取值。

##### Outbound Listener

Envoy为网格中的外部服务按端口创建多个Listener，以用于处理出向请求。

Productpage Pod中的Envoy创建了多个Outbound Listener

* 0.0.0.0_9080 :处理对details,reviews和rating服务的出向请求
* 0.0.0.0_9411 :处理对zipkin的出向请求
* 0.0.0.0_15031 :处理对ingressgateway的出向请求
* 0.0.0.0_3000 :处理对grafana的出向请求
* 0.0.0.0_9093 :处理对citadel、galley、pilot、(Mixer)policy、(Mixer)telemetry的出向请求
* 0.0.0.0_15004 :处理对(Mixer)policy、(Mixer)telemetry的出向请求
* ......

除了9080这个Listener用于处理应用的业务之外，其他listener都是Istio用于处理自身组件之间通信使用的，有的控制面组件如Pilot，Mixer对应多个listener，是因为该组件有多个端口提供服务。

我们这里主要分析一下9080这个业务端口的Listenrer。和Outbound Listener一样，该Listener同样配置了"bind_to_port": false属性，因此该listener也没有被绑定到tcp端口上，其接收到的所有请求都转发自15001端口的Virtual listener。

监听器name为0.0.0.0_9080,推测其含义应为匹配发向任意IP的9080的请求，从[bookinfo程序结构](#bookinfo程序结构)可以看到该程序中的productpage,revirews,ratings,details四个service都是9080端口，那么Envoy如何区别处理这四个service呢？

首先需要区分入向（发送给productpage）请求和出向（发送给其他几个服务）请求：

* 发给productpage的入向请求，virtual listener根据其目的IP和Port首先匹配到[192.168.206.23_9080](#inbound-listener)这个listener上，不会进入0.0.0.0_9080 listener处理。
* 从productpage外发给reviews、details和ratings的出向请求，virtual listener无法找到和其目的IP完全匹配的listener，因此根据通配原则转交给0.0.0.0_9080处理。

> 备注：<br>
 1. 该转发逻辑为根据Envoy配置进行的推测，并未分析Envoy代码进行验证。欢迎了解Envoy代码和实现机制的朋友指正。<br>
 2.根据业务逻辑，实际上productpage并不会调用ratings服务，但Istio并不知道各个业务之间会如何调用，因此将所有的服务信息都下发到了Envoy中。这样做对效率和性能理论上有一定影响，存在一定的优化空间。

由于对应到reviews、details和Ratings三个服务，当0.0.0.0_9080接收到出向请求后，并不能直接发送到一个downstream cluster中，而是需要根据请求目的地进行不同的路由。

在该listener的配置中，我们可以看到并没有像inbound listener那样通过envoy.tcp_proxy直接指定一个downstream的cluster，而是通过rds配置了一个[路由规则9080](#routes)，在路由规则中再根据不同的请求目的地对请求进行处理。

```
{
     "version_info": "2018-09-06T09:34:19Z",
     "listener": {
      "name": "0.0.0.0_9080",
      "address": {
       "socket_address": {
        "address": "0.0.0.0",
        "port_value": 9080
       }
      },
      "filter_chains": [
       {
        "filters": [
         {
          "name": "envoy.http_connection_manager",
          "config": {
           "access_log": [
            {
             "name": "envoy.file_access_log",
             "config": {
              "path": "/dev/stdout"
             }
            }
           ],
           "http_filters": [
            {
             "name": "mixer",
             "config": {
			  
			  ......

             }
            },
            {
             "name": "envoy.cors"
            },
            {
             "name": "envoy.fault"
            },
            {
             "name": "envoy.router"
            }
           ],
           "tracing": {
            "operation_name": "EGRESS",
            "client_sampling": {
             "value": 100
            },
            "overall_sampling": {
             "value": 100
            },
            "random_sampling": {
             "value": 100
            }
           },
           "use_remote_address": false,
           "stat_prefix": "0.0.0.0_9080",
           "rds": {
            "route_config_name": "9080",
            "config_source": {
             "ads": {}
            }
           },
           "stream_idle_timeout": "0.000s",
           "generate_request_id": true,
           "upgrade_configs": [
            {
             "upgrade_type": "websocket"
            }
           ]
          }
         }
        ]
       }
      ],
      "deprecated_v1": {
       "bind_to_port": false
      }
     },
     "last_updated": "2018-09-06T09:34:26.172Z"
    },
    
```

#### Routes

配置Envoy的路由规则。Istio下发的缺省路由规则中对每个端口设置了一个路由规则，根据host来对请求进行路由分发。

下面是9080的路由配置，从文件中可以看到对应了3个virtual host，分别是details、ratings和reviews，这三个virtual host分别对应到不同的[outbound cluster](#outbound-cluster)。
```
{
     "version_info": "2018-09-14T01:38:20Z",
     "route_config": {
      "name": "9080",
      "virtual_hosts": [
       {
        "name": "details.default.svc.cluster.local:9080",
        "domains": [
         "details.default.svc.cluster.local",
         "details.default.svc.cluster.local:9080",
         "details",
         "details:9080",
         "details.default.svc.cluster",
         "details.default.svc.cluster:9080",
         "details.default.svc",
         "details.default.svc:9080",
         "details.default",
         "details.default:9080",
         "10.101.163.201",
         "10.101.163.201:9080"
        ],
        "routes": [
         {
          "match": {
           "prefix": "/"
          },
          "route": {
           "cluster": "outbound|9080||details.default.svc.cluster.local",
           "timeout": "0s",
           "max_grpc_timeout": "0s"
          },
          "decorator": {
           "operation": "details.default.svc.cluster.local:9080/*"
          },
          "per_filter_config": {
           "mixer": {
            ......

           }
          }
         }
        ]
       },
       {
        "name": "ratings.default.svc.cluster.local:9080",
        "domains": [
         "ratings.default.svc.cluster.local",
         "ratings.default.svc.cluster.local:9080",
         "ratings",
         "ratings:9080",
         "ratings.default.svc.cluster",
         "ratings.default.svc.cluster:9080",
         "ratings.default.svc",
         "ratings.default.svc:9080",
         "ratings.default",
         "ratings.default:9080",
         "10.99.16.205",
         "10.99.16.205:9080"
        ],
        "routes": [
         {
          "match": {
           "prefix": "/"
          },
          "route": {
           "cluster": "outbound|9080||ratings.default.svc.cluster.local",
           "timeout": "0s",
           "max_grpc_timeout": "0s"
          },
          "decorator": {
           "operation": "ratings.default.svc.cluster.local:9080/*"
          },
          "per_filter_config": {
           "mixer": {
           ......

            },
            "disable_check_calls": true
           }
          }
         }
        ]
       },
       {
        "name": "reviews.default.svc.cluster.local:9080",
        "domains": [
         "reviews.default.svc.cluster.local",
         "reviews.default.svc.cluster.local:9080",
         "reviews",
         "reviews:9080",
         "reviews.default.svc.cluster",
         "reviews.default.svc.cluster:9080",
         "reviews.default.svc",
         "reviews.default.svc:9080",
         "reviews.default",
         "reviews.default:9080",
         "10.108.25.157",
         "10.108.25.157:9080"
        ],
        "routes": [
         {
          "match": {
           "prefix": "/"
          },
          "route": {
           "cluster": "outbound|9080||reviews.default.svc.cluster.local",
           "timeout": "0s",
           "max_grpc_timeout": "0s"
          },
          "decorator": {
           "operation": "reviews.default.svc.cluster.local:9080/*"
          },
          "per_filter_config": {
           "mixer": {
            ......

            },
            "disable_check_calls": true
           }
          }
         }
        ]
       }
      ],
      "validate_clusters": false
     },
     "last_updated": "2018-09-27T07:17:50.242Z"
    }
```

## Bookinfo端到端调用分析

通过前面章节对Envoy配置文件的分析，我们了解到Istio控制面如何将服务和路由信息通过xDS接口下发到数据面中；并介绍了Envoy上生成的各种配置数据的结构，包括listener,cluster,route和endpoint。

下面我们来分析一个端到端的调用请求，通过调用请求的流程把这些配置串连起来，以从全局上理解Istio控制面的流量控制是如何在数据面的Envoy上实现的。

下图描述了一个Productpage服务调用Details服务的请求流程：

![](https://zhaohuabing.com/img/2018-09-25-istio-traffic-management-impl-intro/envoy-traffic-route.png)  

1. Productpage发起对Details的调用：`http://details:9080/details/0` 。
2. 请求被Pod的iptable规则拦截，转发到15001端口。
3. Envoy的Virtual Listener在15001端口上监听，收到了该请求。
4. 请求被Virtual Listener根据原目标IP（通配）和端口（9080）转发到0.0.0.0_9080这个listener。
```
    {
     "version_info": "2018-09-06T09:34:19Z",
     "listener": {
      "name": "virtual",
      "address": {
       "socket_address": {
        "address": "0.0.0.0",
        "port_value": 15001
       }
      }
      ......

      "use_original_dst": true //请求转发给和原始目的IP:Port匹配的listener
     },
```
5. 根据0.0.0.0_9080 listener的http_connection_manager filter配置,该请求采用“9080” route进行分发。
```
    {
     "version_info": "2018-09-06T09:34:19Z",
     "listener": {
      "name": "0.0.0.0_9080",
      "address": {
       "socket_address": {
        "address": "0.0.0.0",
        "port_value": 9080
       }
      },
      "filter_chains": [
       {
        "filters": [
         {
          "name": "envoy.http_connection_manager",
          "config": {
          ......

           "rds": {
            "route_config_name": "9080",
            "config_source": {
             "ads": {}
            }
           },

         }
        ]
       }
      ],
      "deprecated_v1": {
       "bind_to_port": false
      }
     },
     "last_updated": "2018-09-06T09:34:26.172Z"
    },

    {
     },
```

6. “9080”这个route的配置中，host name为details:9080的请求对应的cluster为outbound|9080||details.default.svc.cluster.local
```
{
     "version_info": "2018-09-14T01:38:20Z",
     "route_config": {
      "name": "9080",
      "virtual_hosts": [
       {
        "name": "details.default.svc.cluster.local:9080",
        "domains": [
         "details.default.svc.cluster.local",
         "details.default.svc.cluster.local:9080",
         "details",
         "details:9080",
         "details.default.svc.cluster",
         "details.default.svc.cluster:9080",
         "details.default.svc",
         "details.default.svc:9080",
         "details.default",
         "details.default:9080",
         "10.101.163.201",
         "10.101.163.201:9080"
        ],
        "routes": [
         {
          "match": {
           "prefix": "/"
          },
          "route": {
           "cluster": "outbound|9080||details.default.svc.cluster.local",
           "timeout": "0s",
           "max_grpc_timeout": "0s"
          },
            ......

           }
          }
         }
        ]
       },
	   ......

    {
     },
```

7. outbound|9080||details.default.svc.cluster.local cluster为动态资源，通过eds查询得到其endpoint为192.168.206.21:9080。
```
{
  "clusterName": "outbound|9080||details.default.svc.cluster.local",
  "endpoints": [
    {
      "locality": {

      },
      "lbEndpoints": [
        {
          "endpoint": {
            "address": {
              "socketAddress": {
                "address": "192.168.206.21",
                "portValue": 9080
              }
            }
          },
         ......  
        }
      ]
    }
  ]
}
```
8. 请求被转发到192.168.206.21，即Details服务所在的Pod，被iptable规则拦截，转发到15001端口。
9. Envoy的Virtual Listener在15001端口上监听，收到了该请求。
10. 请求被Virtual Listener根据请求原目标地址IP（192.168.206.21）和端口（9080）转发到192.168.206.21_9080这个listener。
11. 根据92.168.206.21_9080 listener的http_connection_manager filter配置,该请求对应的cluster为 inbound|9080||details.default.svc.cluster.local 。
```
{
     "version_info": "2018-09-06T09:34:16Z",
     "listener": {
      "name": "192.168.206.21_9080",
      "address": {
       "socket_address": {
        "address": "192.168.206.21",
        "port_value": 9080
       }
      },
      "filter_chains": [
       {
        "filters": [
         {
          "name": "envoy.http_connection_manager",
          ......
          
          "route_config": {
            "name": "inbound|9080||details.default.svc.cluster.local",
            "validate_clusters": false,
            "virtual_hosts": [
             {
              "name": "inbound|http|9080",
              "routes": [
                ......
                
                "route": {
                 "max_grpc_timeout": "0.000s",
                 "cluster": "inbound|9080||details.default.svc.cluster.local",
                 "timeout": "0.000s"
                },
                ......
                
                "match": {
                 "prefix": "/"
                }
               }
              ],
              "domains": [
               "*"
              ]
             }
            ]
           },
            ......
            
           ]
          }
         }
        ]
       }
      ],
      "deprecated_v1": {
       "bind_to_port": false
      }
     },
     "last_updated": "2018-09-06T09:34:22.184Z"
    }
```
12. inbound|9080||details.default.svc.cluster.local cluster配置的host为127.0.0.1：9080。
13. 请求被转发到127.0.0.1：9080，即Details服务进行处理。


上述调用流程涉及的完整Envoy配置文件参见：

* Proudctpage：https://gist.github.com/zhaohuabing/034ef87786d290a4e89cd6f5ad6fcc97
* Details：https://gist.github.com/zhaohuabing/544d4d45447b65d10150e528a190f8ee

# 小结

本文介绍了Istio流量管理相关组件，Istio控制面和数据面之间的标准接口，以及Istio下发到Envoy的完整配置数据的结构和内容。然后通过Bookinfo示例程序的一个端到端调用分析了Envoy是如何实现服务网格中服务发现和路由转发的，希望能帮助大家透过概念更进一步深入理解Istio流量管理的实现机制。

# 参考资料

1. <a id="ref01">[Istio Traffic Managment Concept](https://istio.io/docs/concepts/traffic-management/#pilot-and-envoy)</a>
1. <a id="ref02">[Data Plane API](https://github.com/envoyproxy/data-plane-api/blob/master/API_OVERVIEW.md)</a>
1. <a id="ref03">[kubernetes Custom Resource](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources)</a>
1. <a id="ref04">[Istio Pilot Design Overview](https://github.com/istio/old_pilot_repo/blob/master/doc/design.md)</a>
1. <a id="ref05">[Envoy V2 API Overview](https://www.envoyproxy.io/docs/envoy/latest/configuration/overview/v2_overview)
1. <a id="ref06">[Data Plane API Protocol Buffer Definition](https://github.com/envoyproxy/data-plane-api/tree/master/envoy/api/v2)
1. <a id="ref07">[xDS REST and gRPC protocol](https://github.com/envoyproxy/data-plane-api/blob/master/XDS_PROTOCOL.md)
https://github.com/istio/istio/tree/master/pilot/pkg/proxy/envoy/v2
1. <a id="ref08">[Pilot Debug interface](https://github.com/istio/istio/tree/master/pilot/pkg/proxy/envoy/v2)
1. <a id="ref09">[Istio Sidecar自动注入原理](https://zhaohuabing.com/2018/05/23/istio-auto-injection-with-webhook/)

