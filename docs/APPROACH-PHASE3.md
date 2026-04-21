# Approach — Phase 3: Monitoring and Logging

## Tool selection

### Prometheus over CloudWatch for metrics

CloudWatch is the native AWS monitoring solution. It works well for AWS-managed services like RDS and EC2. However for Kubernetes workloads, CloudWatch requires the CloudWatch agent to be installed on each node and configured separately. Prometheus is the industry standard for Kubernetes monitoring — it was built for containerised environments and integrates natively with Kubernetes through ServiceMonitors and PodMonitors.

Prometheus also gives us full control over what metrics are collected and how long they are retained. CloudWatch pricing is based on the number of metrics and API calls — in a Kubernetes cluster with hundreds of pods this becomes expensive quickly.

### Grafana over AWS native dashboards

AWS provides CloudWatch dashboards but they are limited to AWS metrics only. Grafana can visualise metrics from any source — Prometheus, CloudWatch, Loki, and more — in a single interface. For a platform that may grow beyond AWS, Grafana is the vendor-neutral choice.

### kube-prometheus-stack Helm chart

Instead of installing Prometheus, Grafana, Alertmanager, Node Exporter, and Kube State Metrics separately — the `kube-prometheus-stack` Helm chart installs all of them in a single command with pre-configured integrations.

What the chart installs automatically:
- Prometheus with Kubernetes RBAC permissions
- Grafana with Prometheus pre-configured as data source
- Alertmanager
- Node Exporter as a DaemonSet
- Kube State Metrics
- Pre-built Kubernetes dashboards

This is the standard way companies deploy monitoring on Kubernetes.

---

## Architecture decisions

### Dedicated monitoring namespace

All monitoring components run in the `monitoring` namespace — separate from `staging` and `production`. This gives monitoring its own resource quotas and prevents application deployments from affecting monitoring availability.

### Node Exporter as DaemonSet

Node Exporter runs as a DaemonSet — Kubernetes automatically places one pod on every node. When new nodes are added through autoscaling, Node Exporter is automatically deployed there too. No manual intervention required.

### Prometheus data source pre-configured

The Helm chart automatically configures Grafana with Prometheus as the default data source using the internal Kubernetes service name `kube-prometheus-stack-prometheus:9090`. Grafana communicates with Prometheus over the internal cluster network — no external load balancer needed for this connection.

### LoadBalancer for external Grafana access

Grafana and Prometheus services were patched to `LoadBalancer` type after installation to allow external access for viewing dashboards. In production, these would be exposed via Ingress with TLS and authentication rather than a public load balancer.

---

## Dashboard decisions

### Dashboard 1 — Node Exporter Full (ID: 1860)

Covers infrastructure metrics requirement:
- CPU usage per node
- Memory usage per node
- Disk usage and filesystem metrics
- Network I/O per node
- System load average

Selected this dashboard because it is the most comprehensive Node Exporter dashboard in the Grafana community with over 15 million downloads. It works with the current Prometheus and Node Exporter versions without any modification.

### Dashboard 2 — Kubernetes cluster monitoring (ID: 3119)

Covers application metrics requirement:
- Container CPU usage per pod
- Memory usage per namespace
- Network traffic per container
- Pod count and status

Initially tried dashboard 315 but it showed N/A for all metrics because it uses deprecated metric names from older Prometheus versions. Dashboard 3119 uses current metric names and works correctly.

### Database metrics — AWS CloudWatch

RDS PostgreSQL metrics are available in AWS CloudWatch without any additional configuration. CloudWatch collects:
- CPU utilisation
- Database connections
- Read/write IOPS
- Free storage space
- Replica lag

These metrics trigger the CloudWatch alarms we defined in the RDS Terraform module — CPU above 80% and free storage below 10GB.

---

## Logging decision

### CloudWatch Logs for centralized logging

EKS integrates natively with CloudWatch Logs. Application logs from pods, system logs from nodes, and Kubernetes control plane logs all flow to CloudWatch without any additional agents.

For this assignment, CloudWatch covers the centralized logging requirement:
- Application logs — pod stdout/stderr
- System logs — node-level logs
- Access logs — ALB access logs stored in S3

### Why not Loki

Loki with Promtail is the Grafana-native logging solution — it allows viewing logs directly in Grafana alongside metrics. For this assignment, CloudWatch was used because it requires zero additional configuration on EKS. Loki would require installing Loki and Promtail via Helm, configuring log parsing, and creating Grafana data sources.

In production, Loki would be the preferred choice for a unified observability platform where metrics and logs are both visible in Grafana.

---

## What is different from production banking

| Area | Assignment | Production banking |
|---|---|---|
| Grafana access | Public LoadBalancer | Ingress with TLS and SSO |
| Prometheus storage | Ephemeral (pod storage) | Persistent volume with 30-day retention |
| Alertmanager | Installed but not configured | PagerDuty/Slack alerts configured |
| Logging | CloudWatch | Loki + Promtail in Grafana |
| Dashboard persistence | Manual import | Dashboards as code in Git |
| Metrics retention | 24 hours default | 30-90 days |