# NexaBank IdentityForge Architecture

## Overview

IdentityForge is a zero trust identity and access management platform for NexaBank, a CBN licensed digital bank. It enforces mutual TLS, Keycloak issued JWTs, certificate lifecycle management, and real time anomaly detection across three user populations: staff, field agents, and partner microfinance banks.

## User populations and realms

| Population     | Count | Keycloak realm    | Auth method                                                                       |
| -------------- | ----- | ----------------- | --------------------------------------------------------------------------------- |
| Internal staff | 400   | nexabank-staff    | OIDC authorization code flow with MFA, or SSO                                     |
| Field agents   | 2,000 | nexabank-agents   | Username and password, plus device certificate (mTLS), with a Keycloak issued JWT |
| Partner MFBs   | 12    | nexabank-partners | Client credentials, plus client certificate (mTLS)                                |

## Authentication Methods

| Population   | Primary login                                                                                                                 | Second factor or device proof                                                                                                             | Session                                                                |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Staff        | OIDC authorization code flow in nexabank-staff, with password or company SSO                                                  | MFA (TOTP) required for every staff account, enforced by Keycloak (proposed)                                                              | Access token 5 minutes, SSO session idle timeout 30 minutes (proposed) |
| Field agents | Username and password in nexabank-agents, entered in the app on the bank issued tablet                                        | Device certificate (mTLS). Login requests also pass through the gateway, so a login without the device certificate never reaches Keycloak | Access token 5 minutes, SSO session idle timeout 30 minutes (proposed) |
| Partners     | Client credentials grant in nexabank-partners, client secret held in AWS Secrets Manager and rotated every 90 days (proposed) | Client certificate (mTLS) at the gateway, with the CN equal to the org_id                                                                 | Access token 5 minutes, no refresh token                               |

Common controls on all realms:

- Keycloak brute force detection is enabled. An account is temporarily locked after 5 failed logins, and every failure is logged as an authentication failure (rule 100002).
- Password policy (proposed): minimum 12 characters, common passwords blocked, no reuse of the last 5 passwords.
- Items marked proposed are not fixed by the project brief and need team confirmation.

## Architecture diagram (logical)

```
Field agent tablet / partner system
        ↓   mTLS client certificate + JWT
APISIX gateway
        (TLS termination, certificate chain check, CRL check,
         forwards verified certificate DN in X-Client-Cert-DN)
        ↓
NexaBank API
        (auth.js, mtls.js, roles.js, audit.js)
        ↓                    ↓                      ↓
   Keycloak (3 realms)   PostgreSQL (audit)   Anomaly agent
        ↓                                           ↓
   Smallstep CA                              Wazuh SIEM
   (issuance, revocation, CRL)               (alert intake)
```

## Role hierarchy and delegated administration

### Realm roles

| Realm             | Roles                                            | Notes                                                                          |
| ----------------- | ------------------------------------------------ | ------------------------------------------------------------------------------ |
| nexabank-staff    | staff_admin, compliance, operations, engineering | staff_admin is the only role that can manage staff accounts                    |
| nexabank-agents   | agent, regional_supervisor                       | Every agent belongs to exactly one regional group                              |
| nexabank-partners | partner                                          | One Keycloak client per partner organisation, carrying org_id and partner_tier |

### Regional groups

The agent realm has one group per region: lagos, abuja, kano, port_harcourt, enugu. Each agent is a member of exactly one group. Each regional supervisor is a member of the group they supervise and holds the regional_supervisor role.

### Delegated administration model

A regional supervisor can view, create, disable, enable, and reset credentials only for users in their own regional group. This is implemented with Keycloak fine grained admin permissions scoped to the group (manage members permission on the group, granted by a policy that matches the regional_supervisor role and the supervisor's group). Supervisors hold no realm level admin roles and cannot change roles, clients, or realm settings.

#### Who can do what without full admin rights

| Actor                                 | Can                                                                                             | Cannot                                                                                                                                      |
| ------------------------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Regional supervisor                   | View, create, disable, and enable agents, and reset credentials, in their own region group only | Touch other regions, change roles or groups, edit device_id or certificate attributes, create supervisors, access clients or realm settings |
| Compliance (staff realm)              | Suspend any agent in any region, through the NexaBank API                                       | Create agents or edit Keycloak directly                                                                                                     |
| Provisioning pipeline service account | Write device_id and certificate serial on agent records                                         | Anything else                                                                                                                               |
| Offboarding pipeline service account  | Revoke the certificate, end sessions, disable the account, write the audit record               | Create or edit agents                                                                                                                       |
| Platform admins (2 named people)      | Full realm admin from the bastion host only, for break glass use                                | Act without every action being logged to Wazuh                                                                                              |

#### Create and disable flow

- Create: a supervisor creates the agent in their own region. The region comes from the supervisor's token, not from the request. The account stays disabled until the provisioning pipeline binds the device certificate and enables it.
- Disable: a supervisor or compliance triggers the suspension through the API, which starts the offboarding pipeline: revoke the certificate, end Keycloak sessions, disable the account, write the audit record. Disabling the account alone is not enough, because the tablet's certificate would stay valid.

Alternatives considered and rejected:

- One realm per region: multiplies realms, issuers, and JWKS endpoints by five, and complicates token validation in the API.
- A custom admin endpoint in the NexaBank API that checks the region claim: reimplements Keycloak authorization and bypasses the Keycloak admin event log.

## Token strategy

Access token lifetime is 5 minutes. The API makes authorization decisions from claims alone and does not call Keycloak on each request.

| Claim              | Realms   | Source                                               |
| ------------------ | -------- | ---------------------------------------------------- |
| iss                | all      | Realm URL                                            |
| sub                | all      | Keycloak user or client ID                           |
| aud                | all      | Audience mapper, value `nexabank-api`                |
| exp                | all      | 5 minutes after issue                                |
| iat                | all      | Time of issue                                        |
| realm_access.roles | all      | Realm roles mapper                                   |
| agent_id           | agents   | User attribute                                       |
| region             | agents   | Group membership mapper (name of the regional group) |
| device_id          | agents   | User attribute, written by the provisioning pipeline |
| org_id             | partners | Client attribute                                     |
| partner_tier       | partners | Client attribute, used for gateway rate limits       |

The API validates every request in this order:

1. Signature, checked against the JWKS of the realm named in the iss claim.
2. iss must be one of the three allowed realm URLs, and exp must not have passed.
3. Role check for the route (roles.js).
4. For agents, device_id must equal the CN of the certificate in X-Client-Cert-DN. For partners, org_id must equal the certificate CN.
5. Any failure writes an audit event and returns 401 (authentication) or 403 (authorization).

### JWT validation rules

The API enforces every rule below on every request. A token that fails any rule is rejected, an audit event with event_type `jwt_validation_failure` is written (Wazuh rule 100003), and the response body is generic, with details kept in the audit log only.

| Rule                | Requirement                                                                                                                                                                                                                                                                              | Failure |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| Signature algorithm | RS256 only. The allowed algorithm is fixed in the API and never read from the token header. Tokens using none, HS256, or any other algorithm are rejected.                                                                                                                               | 401     |
| Key lookup          | The kid in the token header must exist in the JWKS of the realm named by iss. The JWKS is cached and refreshed at most once per minute when an unknown kid appears.                                                                                                                      | 401     |
| Issuer              | iss must exactly equal one of the three configured realm URLs, in the form `https://<keycloak host>/realms/<realm>`. No prefix or wildcard matching.                                                                                                                                     | 401     |
| Realm for the route | Agent routes accept only nexabank-agents tokens, staff routes only nexabank-staff, and partner routes only nexabank-partners.                                                                                                                                                            | 403     |
| Audience            | aud must contain `nexabank-api`. Each Keycloak client needs an audience mapper that adds it, because it is not present by default.                                                                                                                                                       | 401     |
| Required claims     | All realms: iss, sub, aud, exp, iat, realm_access.roles. Agents also: agent_id, region, device_id. Partners also: org_id, partner_tier. A missing or empty claim is rejected.                                                                                                            | 401     |
| Expiry              | exp must be in the future. Clock skew tolerance is 30 seconds. exp minus iat must not exceed 300 seconds plus the tolerance, otherwise the token is rejected as misconfigured. nbf, if present, is enforced with the same tolerance. iat must not be in the future beyond the tolerance. | 401     |
| Device binding      | For agents, device_id must equal the CN in X-Client-Cert-DN (a mismatch raises rule 100010). For partners, org_id must equal the CN.                                                                                                                                                     | 403     |

All servers must keep their clocks synced with NTP, since the tolerance is only 30 seconds.

### Keycloak configuration as code

Every realm, client, role, group, mapper, and identity provider setting lives in `keycloak-config/realms/` in the repository. Changes are made by pull request, require approval from the security team (CODEOWNERS), and are applied by a GitHub Actions pipeline. After the Week 1 gate date nobody changes Keycloak through the admin console. Evidence is the git log for the directory and an empty list of console changes in the Keycloak admin event log.

## Token flow

1. The field agent tablet presents its client certificate to the APISIX gateway.
2. APISIX validates the certificate against the NexaBank CA chain, checks the CRL, and forwards the verified subject DN in the `X-Client-Cert-DN` header.
3. The agent authenticates to the nexabank-agents realm in Keycloak using their username and password and receives a JWT.
4. The JWT and the X-Client-Cert-DN header reach `nexabank-api`.
5. `auth.js` validates the JWT signature through JWKS, `mtls.js` validates the X-Client-Cert-DN header, and `roles.js` enforces realm roles.
6. `audit.js` records every request to the file log and to the PostgreSQL `audit_events` table.
7. The anomaly agent reads the audit log as a stream and raises Wazuh alerts.

## Certificate lifecycle

| Event                  | SLA                                | Pipeline                                            |
| ---------------------- | ---------------------------------- | --------------------------------------------------- |
| Device provisioning    | Under 5 minutes per device         | `pipelines/device-provisioning/provision-device.sh` |
| Certificate renewal    | 30 days before expiry (daily cron) | `pipelines/cert-renewal/renew-certs.sh`             |
| Certificate revocation | Request rejected within 60 seconds | CA revoke command, then CRL refresh at the gateway  |
| Session revocation     | Immediate on call                  | `POST /api/agents/revoke-session`                   |
| Full offboarding       | 30 minutes                         | `pipelines/offboarding/offboard-agent.sh`           |

## Security design decisions

**mTLS dual factor**: every agent and partner request requires both a valid JWT and a valid client certificate. Compromise of either alone is insufficient.

**Per realm JWKS**: each Keycloak realm has its own signing key. `auth.js` selects the JWKS endpoint from the `iss` claim, which prevents cross realm token reuse.

**60 second revocation**: the requirement is met by the certificate, not the token. When a certificate is revoked, the CA regenerates the CRL immediately and the gateway pulls it every 30 seconds, so a revoked device is rejected within 60 seconds even though its access token may still be valid for up to 5 minutes. Offboarding also deletes the Keycloak sessions so the token cannot be refreshed. This is verified end to end in acceptance test AT5.

**Region and off hours anomaly detection**: the detection agent uses a sliding window, not batch jobs, to catch attacks as they happen rather than the next morning.

### mTLS rules

The APISIX gateway enforces every rule below on all device facing endpoints (agents and partners). A certificate that fails any rule is rejected at the TLS handshake, the request never reaches the API, and the rejection is logged and forwarded to Wazuh (rule 100004).

| Rule                 | Requirement                                                                                                                                    |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Client cert required | Client verification is set to required, never optional. A connection with no client certificate is rejected.                                   |
| Trusted CA only      | The trust bundle holds only the NexaBank Root CA and Issuing CA. Self signed certificates and certificates from any other CA are rejected.     |
| Chain check          | The full chain must validate back to the NexaBank Root CA. Maximum chain depth is 2 (device, Issuing CA, Root CA).                             |
| Expiry               | Expired and not yet valid certificates are rejected. No grace period. All servers keep clocks synced with NTP.                                 |
| Revocation           | The certificate serial must not appear in the current CRL. If the CRL is older than 5 minutes, device certificates are rejected (fail closed). |
| Key usage            | The certificate must carry the client authentication extended key usage.                                                                       |
| Subject DN           | The DN must match the certificate policy: `CN=<device_id>` with `OU=FieldAgents`, or `CN=<org_id>` with `OU=Partners`.                         |
| TLS version          | TLS 1.2 minimum, TLS 1.3 preferred.                                                                                                            |
| Header handling      | The gateway deletes any X-Client-Cert-DN header sent by a client, then sets it only from the verified certificate.                             |

### Identity forwarding (X-Client-Cert-DN)

After the gateway verifies the client certificate, it passes the verified identity to the NexaBank API in the `X-Client-Cert-DN` header. The value is the full subject DN of the verified certificate, for example `CN=<device_id>,OU=FieldAgents,O=NexaBank,C=NG`. The API reads the CN and OU from it, and compares the CN with device_id (agents) or org_id (partners) in the JWT.

**Trust rule: the API trusts this header only when the request comes from the gateway, never from a direct caller.** This is enforced in three layers:

| Layer   | Control                                                                                                                                         | Owner               |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- |
| Gateway | Deletes any X-Client-Cert-DN sent by a client, then sets it only from the verified certificate.                                                 | Cloud team          |
| Network | The API has no public endpoint. Its security group accepts traffic only from the gateway security group.                                        | Cloud team          |
| API     | The gateway to API connection uses mTLS with a gateway service certificate, and the API accepts the header only on connections that present it. | Cloud and API owner |

API behaviour:

- `REQUIRE_MTLS=true` in every deployed environment. The dev mode that skips this check never runs outside local development.
- If the header is missing, malformed, or the request did not come from the gateway, the API returns 403, writes an `mtls_rejection` audit event, and Wazuh rule 100004 fires.
- If the OU in the header does not match the realm of the JWT (for example an agent token with `OU=Partners`), the request is rejected.
- The audit event records the header value, so every action can be traced to a device.

## Technology stack

| Component             | Technology            |
| --------------------- | --------------------- |
| Identity provider     | Keycloak 23           |
| Database              | PostgreSQL 15         |
| API                   | Node.js 20, Express 4 |
| Certificate authority | Smallstep CA          |
| API gateway           | Apache APISIX         |
| SIEM                  | Wazuh                 |
| IaC                   | Terraform             |
| CI/CD                 | GitHub Actions        |
| Local inference       | Ollama                |

## Implementation Decisions

### API gateway: Apache APISIX

Decision: Apache APISIX (open source) on ECS.

Alternative considered: Kong Gateway (open source edition). Rejected because its client certificate authentication plugin is part of the paid edition, which would force custom Nginx configuration for the core security control of this project.

Reasons: APISIX verifies client certificates against a configured CA natively, supports per consumer rate limiting (limit-count), and can set the X-Client-Cert-DN header from the verified certificate (proxy-rewrite), all in the open source edition.

### Issuing CA: Smallstep CA

Decision: Smallstep CA (step-ca) on EC2, issuing CA key protected by AWS KMS with a customer managed key.

Alternative considered: EJBCA Community. Rejected for this timeline because it is a heavier Java application with its own database, slower to stand up and to script. Its advantage is a built in OCSP responder. We give that up and use CRL for revocation (see PKI Governance).

Reasons: single lightweight service, a CLI that the provisioning, renewal, and offboarding scripts can call directly, support for KMS backed keys, and it is already the CA shown in the architecture.

### Open items to verify before sign off

1. The gateway reloads a refreshed CRL within 30 seconds, and revoke to first rejection is measured under 60 seconds.
2. Smallstep CA is configured to regenerate the CRL on every revocation, and the gateway can reach it.
3. Keycloak 23 fine grained admin permissions is a preview feature that needs the `admin-fine-grained-authz` feature enabled on both Keycloak nodes.
4. TLS handshake rejections happen at the gateway before the API sees a request, so the gateway log must be forwarded to Wazuh with a decoder, otherwise rule 100004 will not fire.
5. The deployed stack matches this section. If the cloud team deployed a different gateway or CA, update the names here and in the rest of the document.
6. Keycloak fine grained permissions may limit what a supervisor can manage in a group but not where they can create users. If so, agent creation must go through the API or a pipeline that takes the region from the supervisor's token.
7. Per partner rate limiting by the partner_tier claim needs the gateway to read the JWT. If that is not feasible in time, rate limit by certificate CN (the org_id) instead.

## PKI Governance

### CA Hierarchy

NexaBank uses a two tier CA hierarchy to separate trust anchor management from day to day certificate operations.

- **Root CA**: Offline and air gapped. Used only to sign the Issuing CA certificate. The private key never touches a networked machine. Stored on encrypted offline media with dual custody access control.
- **Issuing CA**: Online, running Smallstep CA on EC2. Signs all device and partner certificates. The private key is protected by AWS KMS with a customer managed key.

Rationale: if the Issuing CA is compromised, the Root CA remains intact. Mass revocation is possible without losing the trust anchor. Alternative considered: a single tier CA. Rejected because a compromised single CA has no recovery path without reissuing every certificate.

### Chain of Trust

Every device and partner certificate must validate through the chain below. Nothing outside this chain is trusted.

    NexaBank Root CA (offline, self signed)
            ↓ signs
    NexaBank Issuing CA (online, Smallstep CA, key in AWS KMS)
            ↓ signs
    Device and partner certificates

| Level       | Key protection                                  | Signs                           | Lifetime (proposed) | Constraints                                                         |
| ----------- | ----------------------------------------------- | ------------------------------- | ------------------- | ------------------------------------------------------------------- |
| Root CA     | Offline media, dual custody, never on a network | Issuing CA only                 | 10 years            | CA:true, path length 1, key usage keyCertSign and cRLSign           |
| Issuing CA  | AWS KMS customer managed key                    | Device and partner certificates | 3 years             | CA:true, path length 0, key usage keyCertSign and cRLSign           |
| Device cert | Held on the device                              | Nothing                         | 365 days            | CA:false, key usage digitalSignature, extended key usage clientAuth |

Trust rules:

- The gateway trust bundle contains only the Root CA and Issuing CA certificates, and nothing else.
- The Issuing CA certificate cannot sign another CA, because its path length is 0.
- The Root CA publishes its own CRL, updated after each offline ceremony, so a revoked Issuing CA is detected.
- If the Issuing CA is compromised: revoke it from the Root CA, publish the Root CRL, issue a new Issuing CA, reissue all device certificates through the provisioning pipeline, and update the gateway trust bundle.
- Any change to the trust bundle goes through a pull request with security team approval.

### Certificate Policy

| Attribute                      | Value                                                                                                                  |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| Device subject DN              | `CN=<device_id>, O=NexaBank, OU=FieldAgents, C=NG`                                                                     |
| Partner subject DN             | `CN=<org_id>, O=NexaBank, OU=Partners, C=NG`                                                                           |
| Agent to device binding        | Provisioning pipeline writes device_id and certificate serial to the agent's Keycloak record                           |
| Certificate lifetime           | 365 days                                                                                                               |
| Renewal trigger                | 30 days before expiry (automated, daily)                                                                               |
| Key algorithm                  | ECDSA P-256. RSA 2048 only if a tablet cannot support it. Private keys are generated on the device and never leave it. |
| Revocation mechanism           | CRL, regenerated by the CA on every revocation                                                                         |
| Gateway CRL refresh            | Every 30 seconds                                                                                                       |
| CRL backup copy                | Published to S3, refreshed every 6 hours (not used for enforcement)                                                    |
| Maximum revocation propagation | 60 seconds                                                                                                             |

### Enrollment and Identity Proofing

A device receives a certificate only after all of these checks pass:

1. The agent account exists in Keycloak, is disabled, and was created by a supervisor in the agent's own region.
2. The supervisor verifies the agent in person against the HR record, using the employee ID and a government issued ID, and records the check in the audit log.
3. The device is a bank issued tablet registered in the device inventory with a device_id. Unregistered devices are never enrolled.
4. A second person (compliance) approves the enrollment before the pipeline runs.
5. The device generates its own key pair and sends a certificate signing request. The CA accepts it only if the CN equals the registered device_id, the OU is FieldAgents, and the key algorithm is allowed.
6. Each device has one active certificate. Reissuing for the same device revokes the old serial first.
7. The provisioning pipeline writes device_id and the certificate serial to the agent's Keycloak record, enables the account, and writes an audit event to Wazuh.

Partner enrollment: a signed contract, the partner administrator verified by compliance, and one certificate per partner organisation with CN=<org_id>.

Renewal rules: renewal is authenticated with the existing valid certificate, and suspended, revoked, or offboarded agents are never renewed.

### Revocation Triggers

The following events trigger immediate certificate revocation, with a 60 second rejection target:

- Device reported stolen or lost
- Field agent account suspended by the compliance team
- Partner organisation contract terminated
- Certificate private key suspected compromised
- Agent fails re authentication after 3 consecutive attempts

### Revocation SLA (60 seconds)

Revocation must be enforced within 60 seconds, measured from the revoke command to the first rejected request. The budget is shared:

| Step                                                                                   | Owner  | Maximum time                          |
| -------------------------------------------------------------------------------------- | ------ | ------------------------------------- |
| Revoke command runs at the CA (first step of offboarding, never waits for later steps) | DevOps | 5 seconds                             |
| CA regenerates the CRL on revocation                                                   | Cloud  | 5 seconds                             |
| Gateway pulls the new CRL (every 30 seconds)                                           | Cloud  | 30 seconds                            |
| Gateway applies the new CRL                                                            | Cloud  | 5 seconds                             |
| Total                                                                                  |        | 45 seconds, with 15 seconds of margin |

Evidence is acceptance test AT5: a timestamped gateway log showing the measured time.

### Revocation Checking and Fail Closed

The gateway checks every presented certificate against the current CRL. If the gateway cannot refresh the CRL, or the CRL it holds is older than 5 minutes, it rejects device certificates by default (fail closed, not fail open) and raises an alert.

Alternatives considered:

- OCSP as the primary check: rejected because Smallstep CA does not provide an OCSP responder.
- CRL refreshed every 6 hours: rejected because it cannot meet the 60 second requirement.

## STRIDE Threat Model

### Threat Model Scope

Components in scope: Keycloak (three realms), Smallstep CA, APISIX gateway, NexaBank API, Wazuh SIEM, anomaly detection agent, PostgreSQL audit database.

### STRIDE Analysis

#### Spoofing

| Threat                                      | Component    | Mitigation                                                                                                                                                              |
| ------------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Attacker forges a field agent JWT           | NexaBank API | Per realm JWKS validation. The JWT iss claim must match the expected realm URL. Cross realm tokens are rejected.                                                        |
| Attacker presents a self signed certificate | API gateway  | mTLS verifies the certificate chain back to the NexaBank Root CA through the Issuing CA. Self signed certificates are rejected at the TLS handshake.                    |
| Attacker replays a stolen JWT               | NexaBank API | Token lifetime is 5 minutes. A replayed token is useless without the matching device certificate. Session deletion in Keycloak blocks refresh.                          |
| Partner MFB impersonates another partner    | API gateway  | Each partner organisation has a unique client certificate whose CN is the org_id. The API checks that the certificate CN matches the JWT org_id claim on every request. |

#### Tampering

| Threat                                   | Component    | Mitigation                                                                                                                                                                                      |
| ---------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Attacker modifies JWT payload            | NexaBank API | The JWT signature is validated against the Keycloak JWKS on every request. Any modification invalidates the signature.                                                                          |
| Attacker modifies audit log entries      | PostgreSQL   | Audit events are append only. The API service account has no UPDATE or DELETE permission on the `audit_events` table.                                                                           |
| Attacker modifies Keycloak configuration | Keycloak     | The admin console is reachable only from the bastion host. All changes go through pull requests applied by the pipeline from `keycloak-config/realms/`. No manual console changes after Week 1. |

#### Repudiation

| Threat                                       | Component    | Mitigation                                                                                                                                                       |
| -------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Agent denies initiating a transaction        | NexaBank API | Every transaction logs agent ID, device ID (from the certificate CN), timestamp, and request hash to `audit_events`. Certificate binding makes denial difficult. |
| Attacker denies certificate revocation event | Smallstep CA | All CA operations are logged with timestamps. Revocation events reach Wazuh within 30 seconds.                                                                   |

#### Information Disclosure

| Threat                                                  | Component    | Mitigation                                                                                                                       |
| ------------------------------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| Attacker intercepts agent credentials in transit        | Network      | mTLS is enforced on all agent and partner endpoints. TLS 1.2 minimum, TLS 1.3 preferred.                                         |
| Attacker reads audit logs                               | PostgreSQL   | Database sits in a private subnet with no public endpoint. Access is limited to the API service account and the compliance role. |
| Stack traces or internal errors leaked in API responses | NexaBank API | The error handler in `nexabank-clean` returns generic messages in production. Internal details are logged server side only.      |

#### Denial of Service

| Threat                                        | Component    | Mitigation                                                                                                              |
| --------------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Attacker floods partner API endpoints         | API gateway  | Per partner rate limiting at APISIX. The rate limit tier comes from the partner_tier claim.                             |
| Attacker triggers mass certificate revocation | Smallstep CA | CA admin operations need authenticated access from the bastion only. Bulk revocation requires a dual approval workflow. |
| Attacker exhausts Keycloak session pool       | Keycloak     | Token lifetime is 5 minutes. Session limits per user are configurable per realm.                                        |

#### Elevation of Privilege

| Threat                                                             | Component    | Mitigation                                                                                                                                |
| ------------------------------------------------------------------ | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Field agent attempts to access staff endpoints                     | NexaBank API | `roles.js` enforces realm scoped role checks on every route. Agent realm tokens are rejected on staff routes.                             |
| Regional supervisor attempts to manage agents outside their region | Keycloak     | The delegated admin model uses Keycloak groups. The supervisor role is scoped to their group only through fine grained admin permissions. |
| Partner MFB attempts to access agent transaction routes            | NexaBank API | Partner realm tokens carry the partner role only. Transaction routes require the agent role, so partner tokens are rejected.              |
| Attacker abuses a compromised regional supervisor account          | Keycloak     | A supervisor can only manage users in their assigned group and cannot become realm admin. Activity is logged to Wazuh.                    |

## SIEM Integration Plan

### Event Taxonomy

Every security relevant event in NexaBank writes a structured JSON log entry that Wazuh picks up within 30 seconds. The `audit.js` middleware in the NexaBank API already writes in this format. Custom Wazuh rule IDs start at 100000, because lower IDs are reserved for built in Wazuh rules.

| Event type                      | Source               | Wazuh rule ID | Alert level   |
| ------------------------------- | -------------------- | ------------- | ------------- |
| Successful authentication       | Keycloak             | 100001        | Informational |
| Failed authentication           | Keycloak             | 100002        | Medium        |
| JWT validation failure          | NexaBank API         | 100003        | High          |
| mTLS certificate rejection      | API gateway          | 100004        | High          |
| Certificate revocation          | Smallstep CA         | 100005        | High          |
| Certificate renewal             | Smallstep CA         | 100006        | Informational |
| Privilege escalation attempt    | NexaBank API         | 100007        | Critical      |
| Partner rate limit breach       | API gateway          | 100008        | Medium        |
| Anomaly agent alert             | Anomaly agent        | 100009        | Critical      |
| Token with mismatched device ID | NexaBank API         | 100010        | Critical      |
| Agent offboarding triggered     | Offboarding pipeline | 100011        | High          |
| Audit log write failure         | NexaBank API         | 100012        | Critical      |
| Token issuance                  | Keycloak             | 100013        | Informational |
| Keycloak admin action           | Keycloak             | 100014        | Medium        |
| Certificate issuance            | Smallstep CA         | 100015        | Informational |
| Pipeline step failure           | Pipelines            | 100016        | High          |

### Audit Event Format

Every event is one JSON object per line, written to stdout and forwarded to Wazuh within 30 seconds.

| Field       | Description                                                      |
| ----------- | ---------------------------------------------------------------- |
| timestamp   | ISO 8601, UTC                                                    |
| event_type  | For example jwt_validation_failure, mtls_rejection, token_issued |
| source      | keycloak, gateway, api, ca, pipeline                             |
| outcome     | success or failure                                               |
| realm       | nexabank-staff, nexabank-agents, or nexabank-partners            |
| actor_id    | agent_id, staff user, org_id, or service account                 |
| device_id   | Present for agent events                                         |
| cert_serial | Present for certificate events                                   |
| client_ip   | Source address                                                   |
| route       | Route and method for API events                                  |
| reason      | Short failure reason                                             |
| request_id  | Same value across gateway, API, and pipeline logs for one action |

Admin actions also carry action and target. Tokens, passwords, and private keys are never logged.

### Wazuh Detection Rules

Custom rules for the NexaBank threat patterns go in `/var/ossec/etc/rules/nexabank-rules.xml`:

```xml
<group name="nexabank,">

<rule id="100002" level="10" frequency="5" timeframe="60">
  <if_matched_group>authentication_failed</if_matched_group>
  <description>NexaBank: Brute force authentication attempt detected</description>
  <group>nexabank,authentication,brute_force</group>
</rule>

<rule id="100003" level="12">
  <field name="event_type">jwt_validation_failure</field>
  <description>NexaBank: JWT validation failed, possible token forgery or replay</description>
  <group>nexabank,authentication,token</group>
</rule>

<rule id="100004" level="12">
  <field name="event_type">mtls_rejection</field>
  <description>NexaBank: Client certificate rejected at API gateway</description>
  <group>nexabank,pki,mtls</group>
</rule>

<rule id="100007" level="15">
  <field name="event_type">authorization_failure</field>
  <description>NexaBank: Privilege escalation attempt detected</description>
  <group>nexabank,escalation,critical</group>
</rule>

<rule id="100010" level="15">
  <field name="event_type">device_id_mismatch</field>
  <description>NexaBank: JWT device_id does not match certificate CN, possible certificate theft</description>
  <group>nexabank,pki,critical</group>
</rule>

<rule id="100014" level="8">
  <field name="event_type">keycloak_admin_action</field>
  <description>NexaBank: Keycloak admin action recorded</description>
  <group>nexabank,keycloak,admin</group>
</rule>

</group>
```

### 30 Second SLA

Every event must appear in Wazuh within 30 seconds of occurring. This is enforced by:

- `audit.js` writing JSON to stdout on every request
- The Wazuh agent on the same container reading the output through a log file monitor
- Alert forwarding to the Wazuh manager configured with a 10 second flush interval
- The gateway log forwarded to Wazuh for TLS rejection events (rule 100004)

Evidence for the demo: perform an action with the test client, then check the Wazuh dashboard within 30 seconds and confirm the event appears with the correct rule ID.

## Logging Requirements for Pipelines (handoff to DevOps)

Logging is built into the three pipelines from the start, not added afterwards.

- Every pipeline step writes an audit event in the format above with a start time, an end time, and an outcome, using one shared request_id per run.
- Provisioning logs: CSR received, certificate issued (rule 100015), Keycloak record updated, account enabled.
- Renewal logs: each certificate checked, each renewal requested, each success or failure.
- Offboarding logs: trigger received (rule 100011), certificate revoked, sessions ended, account disabled, with the completion time measured against the 30 minute target.
- Any failed step writes a rule 100016 event and stops the pipeline instead of continuing silently.
- Keycloak admin events and CA operations are forwarded to Wazuh by the owners of those services (Cloud).

## CI Security Gates

Every pull request runs these gates in GitHub Actions, except the DAST baseline, which runs on the main branch. A failing gate blocks the merge.

| Gate                  | Tool                                        | Blocks the merge when                                                                                                                                                      | Applies to                   |
| --------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| Secret scanning       | gitleaks                                    | Any secret, key, or token is found in the diff                                                                                                                             | All repositories             |
| Key and cert check    | gitleaks private key rules and a file check | A .pem, .key, .p12, .pfx, or .jks file, or a PRIVATE KEY block, appears in the diff (public certificates are allowed only in a designated certs folder)                    | All repositories             |
| Dependency audit      | npm audit                                   | A high or critical vulnerability is reported                                                                                                                               | NexaBank API                 |
| Container image scan  | Trivy                                       | A critical or high finding that has a fix available                                                                                                                        | API and anomaly agent images |
| Infrastructure scan   | terraform validate, Checkov                 | Any high severity finding                                                                                                                                                  | Terraform                    |
| Keycloak config check | Script over `keycloak-config/realms/`       | A wildcard redirect URI, an access token lifespan other than 300 seconds, or realm admin rights given to supervisors                                                       | Keycloak configuration       |
| Review gate           | CODEOWNERS and branch protection            | A pull request touching `keycloak-config/`, `pipelines/`, the Terraform directory, gateway config, PKI policy, or this document lacks approval from a security team member | Security relevant paths      |
| DAST baseline         | OWASP ZAP baseline scan                     | A High alert is reported against the API in the test environment                                                                                                           | Main branch                  |

Branch protection on main for every security relevant repository: no direct pushes, at least one security team reviewer required, the author cannot approve their own pull request, approvals are dismissed when new commits are pushed, all CI gates must pass, and administrators cannot bypass these rules.

## Security Acceptance Tests

These tests define what "done" means for the security design. Each needs the evidence listed before the demo.

| ID   | Test                                                                         | Pass criteria                                                                                                  | Evidence                                            |
| ---- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| AT1  | Call a transaction route with no token                                       | 401 returned, so auth is not in dev mode                                                                       | Test client output and audit event                  |
| AT2  | Valid JWT, no client certificate                                             | Request rejected                                                                                               | Gateway log and Wazuh rule 100004 within 30 seconds |
| AT3  | Valid client certificate, no JWT                                             | 401 returned                                                                                                   | Test client output and audit event                  |
| AT4  | Self signed certificate at the handshake                                     | Handshake rejected                                                                                             | Gateway log and Wazuh event                         |
| AT5  | Revoke a device certificate, keep sending requests                           | First rejection within 60 seconds of the revoke command                                                        | Timestamped gateway log with measured time          |
| AT6  | Agent token on staff routes, staff token on agent routes                     | 403 returned in both directions                                                                                | Test output and Wazuh rule 100007                   |
| AT7  | Supervisor manages an agent in another region                                | Action denied                                                                                                  | Keycloak admin event in Wazuh (rule 100014)         |
| AT8  | Perform any action with the test client                                      | Event in Wazuh within 30 seconds with the correct rule ID                                                      | Wazuh dashboard screenshot with timestamps          |
| AT9  | Stop one Keycloak node                                                       | Authentication continues without interruption                                                                  | ALB health check and a successful login             |
| AT10 | Review the git log for `keycloak-config/`                                    | Every change came through a pull request, no console changes after the Week 1 gate                             | Git log and Keycloak admin event log                |
| AT11 | Run the test client in anomaly mode                                          | An alert for each of the three models in Wazuh and Slack                                                       | Wazuh rule 100009 events and Slack messages         |
| AT12 | Retest every red team finding after remediation                              | Every finding closed and confirmed resolved                                                                    | D6 report retest column                             |
| AT13 | Send a forged X-Client-Cert-DN directly to the API, then through the gateway | Direct call rejected with 403. Through the gateway, the forged value is overwritten by the real certificate DN | Test output, audit event, Wazuh rule 100004         |

## Red Team Scope (Phase 4)

Testing is limited to the team's own deployed NexaBank environment, with the mentor's approval. No shared infrastructure is tested. The security team runs four attack scenarios and documents each with severity, evidence, remediation, and retest confirmation.

| Scenario                        | What we attempt                                              | Expected detection                                                                                                                                              | Acceptance test |
| ------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| 1. Device authentication bypass | Access the API with a valid JWT but no client certificate    | Request rejected, rule 100004 fires within 30 seconds                                                                                                           | AT2             |
| 2. Certificate forgery          | Present a self signed certificate at the mTLS handshake      | Handshake rejection at the gateway                                                                                                                              | AT4             |
| 3. Privilege escalation         | Use an agent token to access staff admin routes              | Rule 100007 fires, request rejected with 403                                                                                                                    | AT6             |
| 4. Delegated admin abuse        | Use a regional supervisor to manage agents in another region | Keycloak denies the action and records it in the admin event log, forwarded to Wazuh (rule 100014). Rule 100007 does not apply, because the API is not involved | AT7             |
