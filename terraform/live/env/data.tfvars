###############################################################################
# data: Postgres, MySQL, RabbitMQ, Kafka
#
#   terraform apply -var-file=env/core.tfvars -var-file=env/data.tfvars
#
# What this demonstrates in Dash0:
#   - Database spans with real SQL attached. The Dash0 operator auto-instruments
#     the *clients* (the demo app's Java, Node and .NET services), so you see the
#     query, its duration, and which endpoint triggered it, without touching app
#     code.
#   - Messaging trace context propagated across a queue: a producer span in one
#     service linked to a consumer span in another, through RabbitMQ or Kafka.
#     This is the thing that is genuinely painful to build by hand.
#   - Postgres failover: CloudNativePG runs two instances, so deleting the primary
#     pod produces a visible failover in both the metrics and the error rate.
#
# Every chart here claims a PersistentVolume, so the EBS CSI driver must be on
# (it is, by default in the eks-cluster module).
#
# Cost note: six EBS volumes at 8Gi is small, but Kafka and Postgres together
# want real memory. Karpenter is enabled so the cluster grows to fit rather than
# leaving pods Pending.
###############################################################################

enable_karpenter = true

system_node_instance_types = ["m6i.xlarge"]
system_node_min            = 2
system_node_desired        = 2
system_node_max            = 6

profile_data_stores = {
  postgres = true
  mysql    = true
  rabbitmq = true
  kafka    = true
  # ClickHouse and TigerData are off by default: both are memory-hungry and
  # overlap conceptually with Postgres for demo purposes. Turn on individually.
  clickhouse = false
  tigerdata  = false
}

storage_class          = "dash0-gp3"
data_store_volume_size = "8Gi"
