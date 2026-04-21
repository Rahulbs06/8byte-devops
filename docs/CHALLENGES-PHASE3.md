# Challenges — Phase 3: Monitoring and Logging

## 24. Helm repo not found for jenkins user

**What happened**

Added the Prometheus community Helm repo as the `ubuntu` user:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
```

Then tried to install using `sudo -u jenkins helm install ...` and got:
```
Error: INSTALLATION FAILED: repo prometheus-community not found
```

**Why it happened**

Helm stores repository configuration per user in `~/.config/helm/repositories.yaml`. The repo was added for the `ubuntu` user but Jenkins runs as the `jenkins` user — a completely different home directory.

**Resolution**

Added the repo explicitly for the jenkins user:
```bash
sudo -u jenkins helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
sudo -u jenkins helm repo update
```

**Next time**

When running Helm commands as a specific user via `sudo -u`, always ensure repos are added for that same user. Alternatively, install Helm system-wide and configure repos in a shared location.

---

## 25. Dashboard 315 showing N/A for all metrics

**What happened**

Imported Grafana dashboard ID 315 (Kubernetes cluster monitoring via Prometheus). All panels showed N/A — no data was displayed despite Prometheus being connected and collecting metrics.

**Why it happened**

Dashboard 315 was created for an older version of Prometheus and uses deprecated metric names like `container_cpu_usage_seconds_total` with label selectors that no longer exist in current versions. The metric names and label structures changed in newer versions of kube-state-metrics and cadvisor.

**Resolution**

Switched to dashboard ID 3119 which is maintained for current Prometheus versions. It uses updated metric names and displays all data correctly.

**Next time**

Before importing a community dashboard, check its last update date and the Prometheus/Grafana versions it supports. Dashboards not updated in over a year may have compatibility issues with current metric names.

---

## 26. Grafana and Prometheus not accessible externally

**What happened**

After installing kube-prometheus-stack, Grafana and Prometheus were running but not accessible from the browser. All services were of type `ClusterIP` — only accessible inside the cluster.

**Resolution**

Patched both services to `LoadBalancer` type using kubectl:
```bash
kubectl patch svc kube-prometheus-stack-grafana \
  -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'

kubectl patch svc kube-prometheus-stack-prometheus \
  -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

AWS automatically created Classic Load Balancers and assigned public DNS names.

**Production note**

Patching services to LoadBalancer creates one ELB per service — costly and not scalable. In production, use Ingress with the AWS Load Balancer Controller for a single ALB handling all monitoring traffic, with TLS and authentication.

**Next time**

When installing kube-prometheus-stack for external access, set the service type during installation using Helm values:
```bash
helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --set grafana.service.type=LoadBalancer \
  --set prometheus.prometheusSpec.service.type=LoadBalancer
```

This is cleaner than patching after installation.

---

## 27. Grafana admin password management

**What happened**

Set Grafana admin password using `--set grafana.adminPassword=admin123` during Helm installation. This is a weak password and is visible in the Helm command history.

**Production note**

In production, the Grafana admin password should be stored in AWS Secrets Manager and referenced as a Kubernetes secret:

```yaml
grafana:
  admin:
    existingSecret: grafana-admin-secret
    userKey: admin-user
    passwordKey: admin-password
```

The secret is created from Secrets Manager values — never hardcoded in Helm values or command line arguments.

**Resolution for assignment**

Used a simple password for the assignment. Documented the production approach above.