# Production recommendations

This document covers what was implemented for the assignment and what the production-grade version would look like. Every item here is a deliberate simplification made for cost or time reasons — not because the production approach is unknown.

---

## Kubernetes

### Horizontal Pod Autoscaler (HPA)

**What we did:** Fixed replica count of 2 in the deployment manifest.

**Production approach:** Use HPA to automatically scale pods based on CPU or memory usage.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: 8byte-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: 8byte-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

For a banking platform handling variable transaction loads — peak hours vs off-peak — HPA ensures the application scales up automatically under load and scales down to save cost during low traffic.

---

### StatefulSet over Deployment for stateful workloads

**What we did:** Used Deployment for the application.

**Production approach:** For stateful components like databases running inside Kubernetes, use StatefulSet instead of Deployment.

StatefulSet gives each pod a unique stable identity (`pod-0`, `pod-1`) and ordered startup/shutdown. This is critical for databases where pod ordering and stable network identities matter. For our stateless Spring Boot app, Deployment is correct. But if we were running any stateful component inside EKS, StatefulSet would be the right choice.

---

### Ingress over LoadBalancer service type

**What we did:** Used `type: LoadBalancer` on the service. This creates one AWS Classic Load Balancer per service.

**Production approach:** Use a single ALB Ingress with host-based or path-based routing for all services.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: 8byte-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  rules:
  - host: staging.8byte.ai
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: eightbyte-app-service
            port:
              number: 80
```

With `LoadBalancer` type, every service creates its own ELB — in a microservices architecture with 10 services that is 10 load balancers costing ~$200/month. A single ALB Ingress handles all routing for a fraction of the cost.

---

### Liveness and readiness probes

**What we did:** No health checks configured on pods.

**Production approach:** Always define both probes.

```yaml
livenessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
  initialDelaySeconds: 20
  periodSeconds: 5
```

Without probes, Kubernetes sends traffic to pods that have not finished starting up, causing request failures. Liveness probe restarts crashed pods. Readiness probe removes pods from the load balancer until they are ready to serve traffic.

---

### Network policies

**What we did:** No network policies — all pods can communicate with all other pods inside the cluster.

**Production approach:** Restrict pod-to-pod communication using NetworkPolicy.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-only
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: 8byte-app
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: production
```

For a banking platform, a compromised pod should not be able to freely communicate with other pods or namespaces. Network policies enforce the principle of least privilege at the network level.

---

### Node scheduling — taints and tolerations

**What we did:** Pods scheduled on any available node.

**Production approach:** Use node labels, taints, and tolerations to place pods on specific nodes.

For example, dedicate certain nodes to production workloads and others to monitoring:

```yaml
nodeSelector:
  role: production

tolerations:
- key: dedicated
  operator: Equal
  value: production
  effect: NoSchedule
```

This prevents monitoring or batch workloads from consuming resources needed by production pods during peak load.

---

### Resource quotas and LimitRange

**What we did:** Basic resource requests and limits on the deployment.

**Production approach:** Enforce namespace-level quotas so no single team or service can consume all cluster resources.

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: production-limits
  namespace: production
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 250m
      memory: 256Mi
    type: Container
```

LimitRange sets default limits on containers that don't specify them — prevents unbounded resource consumption.

---

### RBAC — Role-Based Access Control

**What we did:** Jenkins uses the default service account with broad cluster access.

**Production approach:** Create a dedicated service account for Jenkins with only the permissions it needs.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-deployer
  namespace: production
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-deploy-role
  namespace: production
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "update", "patch"]
- apiGroups: [""]
  resources: ["services", "pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-deploy-binding
  namespace: production
subjects:
- kind: ServiceAccount
  name: jenkins-deployer
roleRef:
  kind: Role
  name: jenkins-deploy-role
  apiGroup: rbac.authorization.k8s.io
```

Jenkins only needs to update deployments — it should not have access to secrets, configmaps, or other namespaces.

---

## Docker

### Multi-stage builds

**What we did:** Single-stage Dockerfile — copies the JAR built by Jenkins into the image.

**Production approach:** Multi-stage build keeps build tools out of the final image.

```dockerfile
FROM maven:3.9.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn clean package -DskipTests -q

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/target/*.jar app.jar
RUN chown appuser:appgroup app.jar
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

The final image contains only the JRE and the JAR — no Maven, no source code, no build cache. Smaller image, smaller attack surface.

**Why we used single-stage for the assignment:** Jenkins already runs `mvn package` before the Docker build. The JAR exists in the workspace. A multi-stage build would compile the code twice — once in Jenkins, once inside Docker. For the assignment this would be redundant. In a setup without a CI server, multi-stage builds inside Docker make sense.

---

### Distroless or Alpine base images

**What we did:** Used `eclipse-temurin:21-jre-alpine` — already a good choice.

**Production approach:** Consider distroless images for the absolute minimum attack surface.

```dockerfile
FROM gcr.io/distroless/java17-debian12
COPY target/*.jar app.jar
ENTRYPOINT ["app.jar"]
```

Distroless images contain only the application and its runtime dependencies — no shell, no package manager, no system utilities. If an attacker compromises the container, they have nothing to work with.

---

### Non-root user

**What we did:** Created `appuser` and ran the container as that user. This is already implemented correctly.

**Production approach:** Same — always run as non-root. Additionally, make the filesystem read-only:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
```

---

### Image vulnerability scanning

**What we did:** Trivy scans the image inside the Jenkins pipeline before pushing to ECR. ECR also scans on push.

**Production approach:** Add a quality gate — fail the pipeline if HIGH or CRITICAL vulnerabilities are found.

```bash
trivy image --exit-code 1 --severity HIGH,CRITICAL image:tag
```

Currently Trivy generates a report but does not fail the build on findings. For a banking platform, any HIGH or CRITICAL vulnerability should block deployment.

---

