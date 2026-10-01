# NexaBank IdentityForge — Operator Handbook

This handbook is for the team that takes over and runs the platform after the cohort ends. It covers day-to-day operations, incident response, and handover procedures.

---

## 1. Starting the stack

```bash
# Clone the repo and copy env file
cp nexabank-api/.env.example nexabank-api/.env
# Edit .env with real secrets

# Start all services
docker compose up -d

# Watch logs
docker compose logs -f
```

Expected healthy state:
- `nexabank-postgres` — healthy
- `nexabank-keycloak` — healthy (takes ~60 seconds on first start)
- `nexabank-api` — healthy
- `nexabank-anomaly-agent` — running

---

## 2. Realm management

Access the Keycloak admin console at `http://localhost:8080/admin`.
Default credentials are in `.env` (change before going to production).

**Add a new field agent**

```bash
# Using kcadm CLI (from within the Keycloak container)
docker exec -it nexabank-keycloak bash

kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password <admin-password>

kcadm.sh create users -r nexabank-agents \
  -s username="<agent-id>" \
  -s enabled=true \
  -s 'attributes.cert_cn=["<agent-id>"]' \
  -s 'attributes.branch_code=["<branch>"]' \
  -s 'attributes.region=["<region>"]'
```

**Disable an account immediately**

```bash
KC_USER_ID=$(kcadm.sh get users -r nexabank-agents -q username=<agent-id> | jq -r '.[0].id')
kcadm.sh update users/"${KC_USER_ID}" -r nexabank-agents -s enabled=false
```

---

## 3. Certificate operations

**Provision a new device**

```bash
./pipelines/device-provisioning/provision-device.sh <AGENT_ID> <BRANCH_CODE> <REGION>
```

**Run cert renewal scan (dry run)**

```bash
./pipelines/cert-renewal/renew-certs.sh --dry-run
```

**Full agent offboarding (30-min SLA)**

```bash
./pipelines/offboarding/offboard-agent.sh <AGENT_ID> "termination"
```

---

## 4. Anomaly detection

The anomaly agent runs in streaming mode inside Docker. Check alerts:

```bash
docker logs nexabank-anomaly-agent --tail 100 -f
```

Three alert types:
- **volume_spike** — user exceeds 100 requests in 10 minutes
- **region_jump** — same token used from 2+ regions within 5 minutes
- **off_hours_access** — access outside 06:00-22:00 UTC

To adjust thresholds, edit environment variables in `docker-compose.yml` and restart:

```bash
docker compose restart anomaly-agent
```

---

## 5. Incident response runbook

### Stolen tablet (Kano incident scenario)

1. Identify the agent's `AGENT_ID` from the MDM console or HR system.
2. Run offboarding: `./pipelines/offboarding/offboard-agent.sh <AGENT_ID> "stolen-device"`.
3. Verify session revocation completed within 60 seconds by checking `logs/offboarding.log`.
4. Confirm cert revocation: check Smallstep CRL at `https://ca.nexabank.internal/crl`.
5. File a Wazuh incident ticket with the offboarding log as evidence.

### Suspected partner MFB compromise

1. Identify the `partnerId` from the audit log or Keycloak partner registry.
2. Call `POST /api/partners/bulk-revoke` with `{ "partnerId": "...", "reason": "suspected-compromise" }`.
3. Revoke the partner's client certificate from the Smallstep CA.
4. Notify the partner MFB operations team.
5. Re-issue a new cert through `provision-device.sh` after the partner confirms remediation.

---

## 6. Monitoring

| Signal | Where to look |
|--------|--------------|
| API health | `GET /health` (returns 200 if up) |
| Audit log | `/var/log/nexabank/audit.log` (inside `nexabank-api` container) |
| Anomaly alerts | `docker logs nexabank-anomaly-agent` |
| Keycloak admin events | Keycloak admin console > Realm > Events |
| DB connections | `SELECT count(*) FROM pg_stat_activity;` in PostgreSQL |

---

## 7. Handover checklist

Before handing this platform to a new team:

- [ ] Replace all placeholder passwords in `.env` with secrets from AWS Secrets Manager
- [ ] Export Keycloak realm configs to `keycloak-config/realms/*.json` and commit
- [ ] Set up GitHub Actions CI/CD using the workflow stubs in `.github/workflows/`
- [ ] Configure Wazuh agent on the Docker host to ship logs
- [ ] Test the offboarding pipeline end-to-end against the 30-minute SLA
- [ ] Document any custom Keycloak authentication flows added by the team
- [ ] Write at least one runbook per detection model in `docs/runbooks/`
