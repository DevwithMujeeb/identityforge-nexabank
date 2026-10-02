X# NexaBank IdentityForge — Architecture

## Overview

IdentityForge is a zero-trust identity and access management platform for NexaBank, a CBN-licensed digital bank. It enforces mutual TLS, Keycloak-issued JWTs, certificate lifecycle management, and real-time anomaly detection across three user populations: staff, field agents, and partner microfinance banks.

## User populations and realms

| Population     | Count | Keycloak realm    | Auth method               |
| -------------- | ----- | ----------------- | ------------------------- |
| Internal staff | 400   | nexabank-staff    | OIDC password / SSO       |
| Field agents   | 2,000 | nexabank-agents   | mTLS + JWT                |
| Partner MFBs   | 12    | nexabank-partners | mTLS + client credentials |

## Architecture diagram (logical)

```
                    ┌─────────────────────────────────┐
                    │         APISIX / Kong            │
                    │   (TLS termination, XFCC fwd)   │
                    └───────────────┬─────────────────┘
                                    │
                    ┌───────────────▼─────────────────┐
                    │           NexaBank API           │
                    │  auth │ mtls │ roles │ audit     │
                    └──┬────────┬──────────┬───────────┘
                       │        │          │
            ┌──────────▼─┐  ┌───▼──────┐  ┌▼────────────┐
            │  Keycloak  │  │ PostgreSQL│  │ Anomaly     │
            │  (3 realms)│  │  (DB)    │  │ Agent       │
            └────────────┘  └──────────┘  └─────────────┘
                  │                              │
         ┌────────▼────────┐           ┌────────▼────────┐
         │  Smallstep CA   │           │    Wazuh SIEM   │
         │  (cert issuance,│           │  (alert intake) │
         │   CRL/OCSP)     │           └─────────────────┘
         └─────────────────┘
```

## Token flow

1. Field agent tablet presents client cert to APISIX.
2. APISIX validates cert against NexaBank CA and forwards `X-Forwarded-Client-Cert` header.
3. Agent authenticates to Keycloak nexabank-agents realm using device credentials; receives JWT.
4. JWT + XFCC header sent to `nexabank-api`.
5. `auth.js` validates JWT signature via JWKS; `mtls.js` validates XFCC; `roles.js` enforces realm roles.
6. `audit.js` records every request to both file log and PostgreSQL `audit_events` table.
7. Anomaly agent reads audit log in streaming mode and triggers Wazuh alerts.

## Certificate lifecycle

| Event               | SLA                   | Pipeline                                             |
| ------------------- | --------------------- | ---------------------------------------------------- |
| Device provisioning | Manual (immediate)    | `pipelines/device-provisioning/provision-device.sh`  |
| Cert renewal        | 30 days before expiry | `pipelines/cert-renewal/renew-certs.sh` (daily cron) |
| Session revocation  | 60 seconds            | `POST /api/agents/revoke-session`                    |
| Full offboarding    | 30 minutes            | `pipelines/offboarding/offboard-agent.sh`            |

## Security design decisions

**mTLS dual factor**: every agent and partner request requires both a valid JWT and a valid client certificate. Compromise of either alone is insufficient.

**Per-realm JWKS**: each Keycloak realm has its own signing key. `auth.js` auto-selects the correct JWKS endpoint from the `iss` claim, preventing cross-realm token reuse.

**60-second revocation SLA**: Keycloak session deletion propagates to the API within one token refresh cycle (token lifetime is set to 5 minutes in Keycloak, but immediate session deletion blocks active refresh). Mentees must verify this end-to-end.

**Region and off-hours anomaly detection**: the detection agent uses a sliding window, not batch jobs, to catch attacks in real time rather than the next morning.

## Technology stack

| Component             | Technology            |
| --------------------- | --------------------- |
| Identity provider     | Keycloak 23           |
| Database              | PostgreSQL 15         |
| API                   | Node.js 20, Express 4 |
| Certificate authority | Smallstep CA / EJBCA  |
| API gateway           | APISIX or Kong        |
| SIEM                  | Wazuh                 |
| IaC                   | Terraform             |
| CI/CD                 | GitHub Actions        |
| Local inference       | Ollama                |

## PKI Governance

### CA Hierarchy

NexaBank uses a two-tier CA hierarchy to separate trust anchor management from day-to-day certificate operations.

- **Root CA**: Offline, air-gapped. Used only to sign the Issuing CA certificate. Private key never touches a networked machine. Stored on encrypted offline media with dual-custody access control.
- **Issuing CA**: Online, running on Smallstep CA or EJBCA Community on EC2. Signs all device certificates. Private key protected by AWS KMS with a customer-managed key.

Rationale: if the Issuing CA is compromised, the Root CA remains intact. Mass revocation is possible without losing the trust anchor. Alternative considered: single-tier CA. Rejected because a compromised single CA has no recovery path without reissuing every certificate.

### Certificate Policy

| Attribute                             | Value                                                       |
| ------------------------------------- | ----------------------------------------------------------- |
| Subject DN format                     | `CN=<agent_id>, O=NexaBank, OU=FieldAgents, C=NG`           |
| Certificate lifetime                  | 365 days                                                    |
| Renewal trigger                       | 30 days before expiry (automated via daily cron)            |
| Key algorithm                         | RSA 2048 or ECDSA P-256                                     |
| CRL distribution point                | Published to S3, refreshed every 6 hours                    |
| OCSP responder                        | Enabled on Issuing CA, target response time under 5 seconds |
| Maximum acceptable OCSP response time | 30 seconds                                                  |

### Revocation Triggers

The following events trigger immediate certificate revocation with a 60-second SLA:

- Device reported stolen or lost
- Field agent account suspended by compliance team
- Partner organisation contract terminated
- Certificate private key suspected compromised
- Agent fails re-authentication after 3 consecutive attempts

### OCSP and CRL Fallback

Primary revocation check uses OCSP. If OCSP is unavailable, the API gateway falls back to CRL cached from S3. CRL is refreshed every 6 hours. A device presenting a certificate with no valid revocation response is rejected by default (fail-closed, not fail-open).

Alternative considered: CRL only. Rejected because CRL latency can exceed 60-second revocation SLA during high-traffic periods.

---

## STRIDE Threat Model

### Threat Model Scope

Components in scope: Keycloak (three realms), Smallstep CA / EJBCA, APISIX / Kong API gateway, NexaBank API, Wazuh SIEM, anomaly detection agent, PostgreSQL audit database.

### STRIDE Analysis

#### Spoofing

| Threat                                      | Component    | Mitigation                                                                                                                                                 |
| ------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Attacker forges a field agent JWT           | NexaBank API | Per-realm JWKS validation. JWT `iss` claim must match the expected realm URL. Cross-realm tokens rejected.                                                 |
| Attacker presents a self-signed certificate | API gateway  | mTLS configured to verify certificate chain back to NexaBank Issuing CA only. Self-signed certs rejected at TLS handshake.                                 |
| Attacker replays a stolen JWT               | NexaBank API | Token lifetime set to 5 minutes. Session deletion in Keycloak blocks refresh. Short-lived tokens limit replay window.                                      |
| Partner MFB impersonates another partner    | API gateway  | Each partner organisation issued a unique client certificate. Certificate CN contains `org_id`. API validates `org_id` matches JWT claim on every request. |

#### Tampering

| Threat                                   | Component    | Mitigation                                                                                                                                                  |
| ---------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Attacker modifies JWT payload            | NexaBank API | JWT signature validated against Keycloak JWKS on every request. Any modification invalidates the signature.                                                 |
| Attacker modifies audit log entries      | PostgreSQL   | Audit events are append-only. No UPDATE or DELETE permissions granted to the API service account on the `audit_events` table.                               |
| Attacker modifies Keycloak configuration | Keycloak     | Admin console accessible only from bastion host. All configuration changes go through version-controlled Terraform. No manual console changes after Week 1. |

#### Repudiation

| Threat                                       | Component    | Mitigation                                                                                                                                                   |
| -------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Agent denies initiating a transaction        | NexaBank API | Every transaction logs agent ID, device ID (from certificate CN), timestamp, and request hash to `audit_events`. Certificate binding makes denial difficult. |
| Attacker denies certificate revocation event | Smallstep CA | All CA operations logged with timestamps. Revocation events written to Wazuh within 30 seconds.                                                              |

#### Information Disclosure

| Threat                                                  | Component    | Mitigation                                                                                                                |
| ------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------- |
| Attacker intercepts agent credentials in transit        | Network      | mTLS enforced on all agent and partner endpoints. TLS 1.2 minimum, TLS 1.3 preferred.                                     |
| Attacker reads audit logs                               | PostgreSQL   | Database in private subnet. No public endpoint. Access restricted to API service account and compliance role only.        |
| Stack traces or internal errors leaked in API responses | NexaBank API | Error handler in `nexabank-clean` returns generic error messages in production. Internal details logged server-side only. |

#### Denial of Service

| Threat                                        | Component    | Mitigation                                                                                                           |
| --------------------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------- |
| Attacker floods partner API endpoints         | API gateway  | Per-partner rate limiting enforced at APISIX / Kong. Rate limit tier stored in JWT `partner_tier` claim.             |
| Attacker triggers mass certificate revocation | Smallstep CA | CA admin operations require authenticated access from bastion only. Bulk revocation requires dual-approval workflow. |
| Attacker exhausts Keycloak session pool       | Keycloak     | Token lifetime set to 5 minutes. Session limits per user configurable per realm.                                     |

#### Elevation of Privilege

| Threat                                                             | Component    | Mitigation                                                                                                                                  |
| ------------------------------------------------------------------ | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Field agent attempts to access staff endpoints                     | NexaBank API | `roles.js` enforces realm-scoped role checks on every route. Agent realm token rejected on staff routes.                                    |
| Regional supervisor attempts to manage agents outside their region | Keycloak     | Delegated admin model uses Keycloak Groups. Regional supervisor role scoped to their group only via fine-grained admin permissions.         |
| Partner MFB attempts to access agent transaction routes            | NexaBank API | Partner realm tokens carry `partner` role only. Transaction routes require `agent` role. Role check rejects partner tokens on agent routes. |
| Attacker abuses compromised regional supervisor account            | Keycloak     | Supervisor can only manage users within their assigned group. Cannot elevate to realm admin. Activity logged to Wazuh.                      |

---

## SIEM Integration Plan

### Event Taxonomy

Every security-relevant event in NexaBank writes a structured JSON log entry that Wazuh picks up within 30 seconds. The `audit.js` middleware in the NexaBank API already writes in this format.

| Event type                      | Source               | Wazuh rule ID range | Alert level   |
| ------------------------------- | -------------------- | ------------------- | ------------- |
| Successful authentication       | Keycloak             | 91001               | Informational |
| Failed authentication           | Keycloak             | 91002               | Medium        |
| JWT validation failure          | NexaBank API         | 91003               | High          |
| mTLS certificate rejection      | API gateway          | 91004               | High          |
| Certificate revocation          | Smallstep CA         | 91005               | High          |
| Certificate renewal             | Smallstep CA         | 91006               | Informational |
| Privilege escalation attempt    | NexaBank API         | 91007               | Critical      |
| Partner rate limit breach       | API gateway          | 91008               | Medium        |
| Anomaly agent alert             | Anomaly agent        | 91009               | Critical      |
| Token with mismatched device ID | NexaBank API         | 91010               | Critical      |
| Agent offboarding triggered     | Offboarding pipeline | 91011               | High          |
| Audit log write failure         | NexaBank API         | 91012               | Critical      |

### Wazuh Detection Rules

The following custom rules are written for the NexaBank threat patterns and placed in `/var/ossec/etc/rules/nexabank-rules.xml`:

```xml
<!-- Rule 91002: Failed authentication - brute force detection -->
<rule id="91002" level="10" frequency="5" timeframe="60">
  <if_matched_group>authentication_failed</if_matched_group>
  <description>NexaBank: Brute force authentication attempt detected</description>
  <group>nexabank,authentication,brute_force</group>
</rule>

<!-- Rule 91003: JWT validation failure -->
<rule id="91003" level="12">
  <field name="event_type">jwt_validation_failure</field>
  <description>NexaBank: JWT validation failed — possible token forgery or replay</description>
  <group>nexabank,authentication,token</group>
</rule>

<!-- Rule 91004: mTLS certificate rejection -->
<rule id="91004" level="12">
  <field name="event_type">mtls_rejection</field>
  <description>NexaBank: Client certificate rejected at API gateway</description>
  <group>nexabank,pki,mtls</group>
</rule>

<!-- Rule 91007: Privilege escalation attempt -->
<rule id="91007" level="15">
  <field name="event_type">authorization_failure</field>
  <field name="attempted_role">staff_admin|realm_admin</field>
  <description>NexaBank: Privilege escalation attempt detected</description>
  <group>nexabank,escalation,critical</group>
</rule>

<!-- Rule 91010: Token device ID mismatch -->
<rule id="91010" level="15">
  <field name="event_type">device_id_mismatch</field>
  <description>NexaBank: JWT device_id does not match certificate CN — possible certificate theft</description>
  <group>nexabank,pki,critical</group>
</rule>
```

### 30-Second SLA

Every event must appear in Wazuh within 30 seconds of occurring. This is enforced by:

- `audit.js` writing to stdout in JSON format on every request
- Wazuh agent running on the same container, reading stdout via a log file monitor
- Alert forwarding to Wazuh manager configured with a 10-second flush interval

Evidence for the demo: perform an action using the test client, then check the Wazuh dashboard within 30 seconds and confirm the event appears with the correct rule ID.

### Red Team Scope (Week 2)

The security team runs four attack scenarios in Week 2 and documents each with severity, evidence, remediation, and re-test confirmation:

| Scenario                        | What we attempt                                            | Expected detection                                    |
| ------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------- |
| 1. Device authentication bypass | Access API with valid JWT but no client certificate        | Rule 91004 fires within 30 seconds                    |
| 2. Certificate forgery          | Present self-signed certificate at mTLS handshake          | TLS handshake rejection at API gateway                |
| 3. Privilege escalation         | Use agent token to access staff admin routes               | Rule 91007 fires, request rejected with 403           |
| 4. Delegated admin abuse        | Use regional supervisor to manage agents in another region | Keycloak group policy blocks action, Rule 91007 fires |
