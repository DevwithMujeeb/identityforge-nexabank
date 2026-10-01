# IdentityForge — NexaBank Capstone (Team 1)

**Expadox Lab Cohort 3 | Cybersecurity Track**

NexaBank is a CBN-licensed digital bank with 400 staff, 2,000 field agents on tablets, and 12 partner microfinance banks. This capstone builds their zero-trust identity and access management platform from scratch.

---

## What you are building

A live, production-grade identity platform that stays running after the cohort ends. It includes:

- Keycloak 23 with three separate realms (staff, agents, partners)
- Mutual TLS for all agent and partner API calls
- JWT validation with per-realm JWKS endpoints
- Certificate lifecycle: provisioning, renewal, revocation, offboarding
- Real-time anomaly detection (volume, region-jump, off-hours)
- PostgreSQL audit trail
- Automated pipelines with SLA assertions

---

## Repository structure

```
identityforge-nexabank/
├── nexabank-api/          # Node.js API — auth, mTLS, roles, audit, routes
│   ├── src/
│   │   ├── index.js
│   │   ├── middleware/    # auth.js, mtls.js, roles.js, audit.js
│   │   ├── routes/        # transactions.js, agents.js, partners.js, health.js
│   │   └── utils/         # logger.js
│   ├── Dockerfile
│   ├── package.json
│   └── .env.example
├── apps/
│   └── test-client/       # Python test client (all four modes)
├── pipelines/
│   ├── device-provisioning/   # provision-device.sh
│   ├── cert-renewal/          # renew-certs.sh
│   └── offboarding/           # offboard-agent.sh
├── detection/
│   ├── agents/                # anomaly-agent.py
│   ├── baselines/             # (add your baseline files here)
│   ├── alerts/                # (populated by anomaly agent)
│   └── Dockerfile.anomaly
├── infrastructure/
│   └── db/schema.sql          # PostgreSQL schema
├── keycloak-config/
│   └── realms/                # Drop realm JSON exports here
├── docs/
│   ├── architecture.md
│   └── operator-handbook.md
└── docker-compose.yml
```

---

## Quick start

```bash
# 1. Copy and configure env
cp nexabank-api/.env.example nexabank-api/.env
# Edit .env — fill in real Keycloak admin password and DB password

# 2. Start the stack
docker compose up -d

# 3. Wait for Keycloak (~60s first start), then check health
curl http://localhost:3000/health

# 4. Run the test client
cd apps/test-client
pip install -r requirements.txt
python test-client.py --mode agent
```

---

## Deliberate challenges for mentees

Each file contains `TODO (mentee challenge)` comments. Key ones:

| File | Challenge |
|------|-----------|
| `routes/agents.js` | Implement cert-CN-to-Keycloak-user binding check |
| `routes/agents.js` | Measure session revocation under 60-second SLA |
| `routes/partners.js` | Enforce `partner_id` claim isolation (MFB-A cannot read MFB-B) |
| `routes/transactions.js` | Persist to PostgreSQL and enforce per-realm transaction limits |
| `pipelines/device-provisioning/provision-device.sh` | Wire real Smallstep `step ca sign` |
| `pipelines/offboarding/offboard-agent.sh` | Wire real `kcadm.sh` + `step ca revoke` + MDM |
| `detection/agents/anomaly-agent.py` | Post alerts to Wazuh Active Response socket |

---

## SLA requirements (from brief)

| SLA | Target | How to verify |
|-----|--------|---------------|
| Token revocation | 60 seconds | `python test-client.py --mode revoke` |
| Full offboarding | 30 minutes | `./pipelines/offboarding/offboard-agent.sh` logs elapsed time |
| Detection alert latency | Real-time (stream mode) | `docker logs nexabank-anomaly-agent` |

---

## Technology stack

Keycloak 23 · PostgreSQL 15 · Node.js 20 · Python 3.11 · Smallstep CA · APISIX / Kong · Wazuh · Terraform · GitHub Actions
