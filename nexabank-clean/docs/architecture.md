# NexaBank IdentityForge — Architecture

## Overview

IdentityForge is a zero-trust identity and access management platform for NexaBank, a CBN-licensed digital bank. It enforces mutual TLS, Keycloak-issued JWTs, certificate lifecycle management, and real-time anomaly detection across three user populations: staff, field agents, and partner microfinance banks.

## User populations and realms

| Population | Count | Keycloak realm | Auth method |
|------------|-------|----------------|-------------|
| Internal staff | 400 | nexabank-staff | OIDC password / SSO |
| Field agents | 2,000 | nexabank-agents | mTLS + JWT |
| Partner MFBs | 12 | nexabank-partners | mTLS + client credentials |

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

| Event | SLA | Pipeline |
|-------|-----|----------|
| Device provisioning | Manual (immediate) | `pipelines/device-provisioning/provision-device.sh` |
| Cert renewal | 30 days before expiry | `pipelines/cert-renewal/renew-certs.sh` (daily cron) |
| Session revocation | 60 seconds | `POST /api/agents/revoke-session` |
| Full offboarding | 30 minutes | `pipelines/offboarding/offboard-agent.sh` |

## Security design decisions

**mTLS dual factor**: every agent and partner request requires both a valid JWT and a valid client certificate. Compromise of either alone is insufficient.

**Per-realm JWKS**: each Keycloak realm has its own signing key. `auth.js` auto-selects the correct JWKS endpoint from the `iss` claim, preventing cross-realm token reuse.

**60-second revocation SLA**: Keycloak session deletion propagates to the API within one token refresh cycle (token lifetime is set to 5 minutes in Keycloak, but immediate session deletion blocks active refresh). Mentees must verify this end-to-end.

**Region and off-hours anomaly detection**: the detection agent uses a sliding window, not batch jobs, to catch attacks in real time rather than the next morning.

## Technology stack

| Component | Technology |
|-----------|-----------|
| Identity provider | Keycloak 23 |
| Database | PostgreSQL 15 |
| API | Node.js 20, Express 4 |
| Certificate authority | Smallstep CA / EJBCA |
| API gateway | APISIX or Kong |
| SIEM | Wazuh |
| IaC | Terraform |
| CI/CD | GitHub Actions |
| Local inference | Ollama |
