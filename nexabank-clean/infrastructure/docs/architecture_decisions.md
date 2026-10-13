# Architecture Decisions & System Design: IdentityForge

This document outlines the architectural patterns, security models, infrastructure resilience strategies, and trade-offs evaluated during the design of **IdentityForge**.

---

## 1. Core Architecture Overview
* **Networking:** Multi-AZ VPC featuring:
  * **Public Subnets:** Housing the Application Load Balancer (ALB) and the Bastion Host (managed via an ASG).
  * **Private Subnets:** Housing the Keycloak instances (managed via an ASG) and the Smallstep CA PKI instance (managed via an ASG).
  * **Private/Isolated Subnets:** Housing the RDS PostgreSQL database with zero direct exposure to the public internet.
* **Compute & Services:** 
  * **API Gateway:** Containerized via Amazon ECS behind a single public Application Load Balancer (ALB).
  * **Authentication & Control Plane:** Keycloak, Bastion Host, and Smallstep CA instances are provisioned and managed using **Auto Scaling Groups (ASGs)** to ensure automated lifecycle management and self-healing.

---

## 2. Infrastructure Resilience & High Availability

### Dynamic Auto Scaling & Self-Healing (ASG)
IdentityForge leverages native AWS Auto Scaling Groups across core components to balance cost optimization with enterprise-grade resilience:
* **Cost-Optimized Minimum Capacity (`min_size = 1`):** Services like Keycloak, the Bastion host, and the Smallstep CA are configured with a minimum capacity of 1 to minimize idle baseline expenses. The ASG dynamically scales out or provisions fresh instances automatically in response to high traffic demands or underlying infrastructure/health check failures.
* **Database Resiliency:** The RDS PostgreSQL database is deployed in a Multi-AZ configuration within an isolated private subnet, providing synchronous replication and automated failover with zero data loss.

---

## 3. Key Design Trade-Offs

### Trade-Off 1: Single-Region Multi-AZ vs. Multi-Region Active-Active DR
* **Decision:** Constrained deployment to a single primary AWS region utilizing Multi-AZ resilience.
* **Rationale:** Full multi-region replication introduces prohibitive cost overheads (idle duplicate compute resources and heavy cross-region data transfer fees) which are unnecessary for a lean production build. 
* **Mitigation:** Rely on **Terraform** as an infrastructure blueprint combined with automated RDS snapshots and S3 backups to achieve a code-driven "Backup & Restore" strategy for catastrophic regional failures.

### Trade-Off 2: ASG-Backed Control-Plane Nodes (Bastion & PKI)
* **Decision:** Managed the **Bastion Host** and **Smallstep CA PKI server** through Auto Scaling Groups with strict minimum capacities rather than manual standalone instances.
* **Rationale:** While control-plane nodes require predictable management, utilizing ASGs ensures automated recovery and self-healing if a host experiences hardware failure.
* **Mitigation:** Secured via strict private subnet isolation, security group micro-segmentation, and KMS-backed master keys to ensure cryptographic state remains safe and uncompromised across instance lifecycle events.

### Trade-Off 3: Lean Baseline Compute Capacity
* **Decision:** Optimized baseline compute allocations to a minimum size of 1 while retaining dynamic scaling capabilities.
* **Rationale:** Balancing baseline cloud costs against high-availability demands for student/lean production environments.
* **Mitigation:** Utilizing self-healing ASG rules to manage operational health efficiently and scale up only when triggered by traffic spikes or node failures.