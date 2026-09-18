###############################################################################
# Data stores
#
# Every chart here claims a PersistentVolume, so the EBS CSI driver must be
# enabled on the cluster. Sizes are deliberately small.
#
# The observability angle: Dash0 auto-instruments the *clients* of these stores
# (Java/Node/Python/.NET), so database spans show up with real SQL statements
# attached. The stores themselves contribute Prometheus metrics.
###############################################################################

###############################################################################
# PostgreSQL via CloudNativePG
#
# An operator rather than a single Helm-managed StatefulSet, because the
# failover and backup story is what makes Postgres interesting to observe.
###############################################################################

module "postgres_operator" {
  source = "../helm-addon"

  enabled = var.data_stores.postgres

  release_name  = local.catalog.postgres_operator.release
  repository    = local.catalog.postgres_operator.repository
  chart         = local.catalog.postgres_operator.chart
  chart_version = local.catalog.postgres_operator.version
  namespace     = local.catalog.postgres_operator.namespace

  values = {
    replicaCount = 1
    resources    = local.medium_resources

    monitoring = {
      # The operator can create a PodMonitor for each Cluster it manages. Only
      # valid if the CRD exists.
      podMonitorEnabled = var.observability.prometheus_stack
      grafanaDashboard = {
        create = false
      }
    }
  }
}

# The actual database. CloudNativePG exposes a Prometheus endpoint on 9187 for
# every instance.
resource "kubernetes_manifest" "postgres_cluster" {
  count = var.data_stores.postgres ? 1 : 0

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = "demo-pg"
      namespace = local.catalog.postgres_operator.namespace
    }
    spec = {
      # Two instances so failover is demonstrable without a big bill.
      instances = 2

      storage = {
        size         = local.storage.size
        storageClass = local.storage.class
      }

      monitoring = {
        enablePodMonitor = var.observability.prometheus_stack
      }

      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }

      postgresql = {
        parameters = {
          # Logging every statement is far too noisy for production but makes
          # the log pipeline into Dash0 immediately visible.
          log_statement              = "all"
          log_min_duration_statement = "0"
        }
      }
    }
  }

  depends_on = [module.postgres_operator]
}

###############################################################################
# MySQL
###############################################################################

module "mysql" {
  source = "../helm-addon"

  enabled = var.data_stores.mysql

  release_name  = local.catalog.mysql.release
  repository    = local.catalog.mysql.repository
  chart         = local.catalog.mysql.chart
  chart_version = local.catalog.mysql.version
  namespace     = local.catalog.mysql.namespace

  values = {
    architecture = "standalone"

    auth = {
      # Chart generates a random root password into a Secret. Nothing sensitive
      # ends up in Terraform state this way.
      database = "demo"
      username = "demo"
    }

    primary = {
      persistence = {
        enabled      = true
        size         = local.storage.size
        storageClass = local.storage.class
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
    }

    metrics = {
      enabled = true
      serviceMonitor = {
        enabled = var.observability.prometheus_stack
      }
      # mysqld-exporter listens on 9104.
      annotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "9104"
      }
    }
  }
}

###############################################################################
# RabbitMQ
#
# Good for showing messaging spans: the Dash0 auto-instrumentation links
# producer and consumer traces across the queue.
###############################################################################

module "rabbitmq" {
  source = "../helm-addon"

  enabled = var.data_stores.rabbitmq

  release_name  = local.catalog.rabbitmq.release
  repository    = local.catalog.rabbitmq.repository
  chart         = local.catalog.rabbitmq.chart
  chart_version = local.catalog.rabbitmq.version
  namespace     = local.catalog.rabbitmq.namespace

  values = {
    replicaCount = 1

    persistence = {
      enabled      = true
      size         = local.storage.size
      storageClass = local.storage.class
    }

    metrics = {
      enabled = true
      serviceMonitor = {
        enabled = var.observability.prometheus_stack
      }
    }

    podAnnotations = {
      "prometheus.io/scrape" = "true"
      # The rabbitmq_prometheus plugin serves on 9419.
      "prometheus.io/port" = "9419"
    }

    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { memory = "1Gi" }
    }
  }
}

###############################################################################
# Kafka via Strimzi
###############################################################################

module "strimzi" {
  source = "../helm-addon"

  enabled = var.data_stores.kafka

  release_name  = local.catalog.strimzi.release
  repository    = local.catalog.strimzi.repository
  chart         = local.catalog.strimzi.chart
  chart_version = local.catalog.strimzi.version
  namespace     = local.catalog.strimzi.namespace

  values = {
    # Watch only its own namespace, keeping RBAC narrow.
    watchNamespaces = []
    resources       = local.medium_resources
  }
}

# KRaft mode: no ZooKeeper. One combined broker/controller node is enough here.
resource "kubernetes_manifest" "kafka_node_pool" {
  count = var.data_stores.kafka ? 1 : 0

  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaNodePool"
    metadata = {
      name      = "dual-role"
      namespace = local.catalog.strimzi.namespace
      labels = {
        "strimzi.io/cluster" = "demo-kafka"
      }
    }
    spec = {
      replicas = 1
      roles    = ["controller", "broker"]
      storage = {
        type = "jbod"
        volumes = [
          {
            id          = 0
            type        = "persistent-claim"
            size        = local.storage.size
            class       = local.storage.class
            deleteClaim = true
          }
        ]
      }
    }
  }

  depends_on = [module.strimzi]
}

resource "kubernetes_manifest" "kafka_cluster" {
  count = var.data_stores.kafka ? 1 : 0

  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "Kafka"
    metadata = {
      name      = "demo-kafka"
      namespace = local.catalog.strimzi.namespace
      annotations = {
        "strimzi.io/node-pools" = "enabled"
        "strimzi.io/kraft"      = "enabled"
      }
    }
    spec = {
      kafka = {
        listeners = [
          {
            name = "plain"
            port = 9092
            type = "internal"
            tls  = false
          }
        ]
        config = {
          # Single broker, so nothing can be replicated further than that.
          "offsets.topic.replication.factor"         = 1
          "transaction.state.log.replication.factor" = 1
          "transaction.state.log.min.isr"            = 1
          "default.replication.factor"               = 1
          "min.insync.replicas"                      = 1
        }
        resources = {
          requests = { cpu = "200m", memory = "512Mi" }
          limits   = { memory = "2Gi" }
        }
      }
      entityOperator = {
        topicOperator = {}
        userOperator  = {}
      }
    }
  }

  depends_on = [kubernetes_manifest.kafka_node_pool]
}

###############################################################################
# ClickHouse via the Altinity operator
###############################################################################

module "clickhouse_operator" {
  source = "../helm-addon"

  enabled = var.data_stores.clickhouse

  release_name  = local.catalog.clickhouse_operator.release
  repository    = local.catalog.clickhouse_operator.repository
  chart         = local.catalog.clickhouse_operator.chart
  chart_version = local.catalog.clickhouse_operator.version
  namespace     = local.catalog.clickhouse_operator.namespace

  values = {
    metrics = {
      enabled = true
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "8888"
      }
    }
    resources = local.medium_resources
  }
}

resource "kubernetes_manifest" "clickhouse_installation" {
  count = var.data_stores.clickhouse ? 1 : 0

  manifest = {
    apiVersion = "clickhouse.altinity.com/v1"
    kind       = "ClickHouseInstallation"
    metadata = {
      name      = "demo-ch"
      namespace = local.catalog.clickhouse_operator.namespace
    }
    spec = {
      configuration = {
        clusters = [
          {
            name = "demo"
            layout = {
              shardsCount   = 1
              replicasCount = 1
            }
          }
        ]
      }
      defaults = {
        templates = {
          dataVolumeClaimTemplate = "data"
        }
      }
      templates = {
        volumeClaimTemplates = [
          {
            name = "data"
            spec = {
              accessModes      = ["ReadWriteOnce"]
              storageClassName = local.storage.class
              resources = {
                requests = {
                  storage = local.storage.size
                }
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [module.clickhouse_operator]
}

###############################################################################
# TigerData (TimescaleDB)
###############################################################################

module "tigerdata" {
  source = "../helm-addon"

  enabled = var.data_stores.tigerdata

  release_name  = local.catalog.tigerdata.release
  repository    = local.catalog.tigerdata.repository
  chart         = local.catalog.tigerdata.chart
  chart_version = local.catalog.tigerdata.version
  namespace     = local.catalog.tigerdata.namespace

  values = {
    # Single instance; the HA story needs three and a lot more memory.
    replicaCount = 1

    persistentVolumes = {
      data = {
        size         = local.storage.size
        storageClass = local.storage.class
      }
      wal = {
        size         = local.storage.size
        storageClass = local.storage.class
      }
    }

    prometheus = {
      enabled = true
    }

    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { memory = "1Gi" }
    }
  }

  # The chart runs an init job that can be slow on a cold node.
  timeout = 900
}
