
---

# Phase 2 — CI/CD Pipeline

## 15. Jenkins 2.555.1 requires Java 21

**What happened**

Installed Java 17 first then Jenkins. Jenkins failed to start with:
```
Running with Java 17 which is older than the minimum required version (Java 21)
```

**Resolution**

Installed Java 21 alongside Java 17. Set Java 21 as default using `update-alternatives`. Updated the Jenkins systemd service file to point `JAVA_HOME` to the Java 21 path. Jenkins started successfully.

**Next time**

Always check the Jenkins release notes for minimum Java version before installing. As of Jenkins 2.426+, Java 21 is required.

---

## 16. Jenkins GPG key installation failing

**What happened**

Standard Jenkins installation commands failed with:
```
NO_PUBKEY 7198F4B714ABFC68
The repository is not signed
```

Multiple attempts with different key import methods failed.

**Resolution**

Used `apt-key adv` to import the key directly from the Ubuntu keyserver:
```bash
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 7198F4B714ABFC68
```

**Next time**

When standard `wget` key import fails, use `apt-key adv` with the Ubuntu keyserver as fallback.

---

## 17. SonarQube webhook unreachable from Jenkins

**What happened**

Jenkins pipeline hung at the `quality gate` stage. SonarQube was configured with the Jenkins public IP in the webhook URL. SonarQube could not reach Jenkins because the Jenkins security group only allowed port 8080 from our local IP — not from SonarQube.

**Resolution**

Two fixes applied:
1. Updated SonarQube webhook URL to use Jenkins private IP `10.0.1.216` instead of public IP
2. Added security group rule to allow port 8080 from the `10.0.1.0/24` subnet so SonarQube could call back to Jenkins

**Next time**

When servers are in the same VPC, always use private IPs for communication between them. Public IPs add unnecessary network hops and security group complexity.

---

## 18. Circular dependency in security groups

**What happened**

Tried to add a rule allowing SonarQube security group to reach Jenkins security group on port 8080. Simultaneously, Jenkins security group already referenced SonarQube security group. Terraform threw:
```
Error: Cycle: aws_security_group.sonarqube, aws_security_group.jenkins
```

**Resolution**

Replaced the security group reference with a CIDR block for the entire subnet `10.0.1.0/24`. Both Jenkins and SonarQube are in this subnet so this achieves the same result without circular dependency.

**Next time**

When two security groups need to reference each other, use CIDR blocks instead of security group IDs to avoid circular dependencies.

---

## 19. Spring Boot version incompatible with source code

**What happened**

Upgraded `pom.xml` from Spring Boot 2.5.6 to 3.2.5 hoping to fix Java compatibility. Build failed with:
```
package javax.servlet does not exist
cannot find symbol: class WebSecurityConfigurerAdapter
```

Spring Boot 3.x replaced `javax.servlet` with `jakarta.servlet` and removed `WebSecurityConfigurerAdapter`. The source code was written for Spring Boot 2.x and would need significant refactoring.

**Resolution**

Reverted to Spring Boot 2.7.18 — the last stable 2.x release — which supports Java 17 and is compatible with the existing source code without any changes.

**Next time**

As a DevOps engineer, never upgrade application framework versions without developer involvement. Our responsibility is to build and deploy the code as written, not to refactor it. Always check framework compatibility before changing versions.

---

## 20. Kubernetes service name starting with a number

**What happened**

Named the service `8byte-app-service`. Kubernetes rejected it with:
```
a DNS-1035 label must consist of lower case alphanumeric characters or '-',
start with an alphabetic character
```

**Resolution**

Renamed to `eightbyte-app-service` — starts with a letter, fully compliant with DNS-1035.

**Next time**

Kubernetes resource names follow DNS-1035 rules — must start with a letter, contain only lowercase alphanumeric characters and hyphens. Never start a resource name with a number.

---

## 21. PR builds running full deployment pipeline

**What happened**

Used `when { branch 'main' }` to skip deployment stages for PR builds. In a multibranch pipeline, PR builds run under the name `PR-1` not the source branch name `feature/test-pr`. So the condition evaluated incorrectly and all stages ran on PR builds including deploy to staging and manual approval.

**Resolution**

Replaced `when { branch 'main' }` with `when { not { changeRequest() } }`. The `changeRequest()` function returns true when the build is triggered by a pull request, regardless of branch name. This correctly skips deployment stages for all PR builds.

**Next time**

In Jenkins multibranch pipelines, use `changeRequest()` to detect PR builds — not branch name conditions. Branch name conditions do not work reliably for PR builds.

---

## 22. Docker permission denied for ubuntu user

**What happened**

After running `sudo usermod -aG docker ubuntu`, the ubuntu user still got permission denied when running docker commands. The `docker run` command failed immediately.

**Resolution**

The group membership change only takes effect in new login sessions. The current SSH session still had old group memberships. Used `sudo docker` as a workaround. Logged out and back in for subsequent commands to work without sudo.

**Next time**

After adding a user to the docker group, always either log out and log back in, or run `newgrp docker` to activate the new group in the current session.

---

## 23. GitHub webhook not triggering Jenkins

**What happened**

Configured GitHub webhook pointing to `http://43.205.196.131:8080/github-webhook/`. Webhook showed "This hook has never been triggered" with a grey dot. GitHub could not reach Jenkins because port 8080 was restricted to our local IP only.

**Resolution**

Updated the Jenkins security group to allow port 8080 from `0.0.0.0/0` so GitHub's servers can reach Jenkins for webhook delivery.

**Next time**

Jenkins port 8080 must be open to the internet for GitHub webhooks to work. In production, restrict this further using GitHub's published IP ranges instead of all IPs.