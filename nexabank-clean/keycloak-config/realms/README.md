# NexaBank Keycloak Realm Configuration

Place your exported Keycloak realm JSON files here. Keycloak imports them on first start via `--import-realm`.

## Required files

| File | Realm | Purpose |
|------|-------|---------|
| `nexabank-staff.json` | nexabank-staff | 400 internal staff accounts |
| `nexabank-agents.json` | nexabank-agents | 2,000 field agent accounts + mTLS binding |
| `nexabank-partners.json` | nexabank-partners | 12 partner MFB client credentials |

## How to export an existing realm

```bash
/opt/keycloak/bin/kcreg.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password <admin-password>

/opt/keycloak/bin/kcreg.sh get nexabank-staff > keycloak-config/realms/nexabank-staff.json
```

## Key custom attributes to configure per realm

**nexabank-agents realm** — each user needs:
- `cert_cn`: matches the CN of their tablet client certificate
- `branch_code`: e.g. `KN-001` (Kano branch)
- `region`: e.g. `north-west`

**nexabank-partners realm** — each client needs:
- `partner_id`: unique MFB identifier (also mapped to token claim)
- `mfb_code`: CBN-issued microfinance bank code

## Token lifetime settings (from capstone brief)

| Realm | Access token lifetime | Refresh token lifetime |
|-------|-----------------------|------------------------|
| nexabank-staff | 5 minutes | 8 hours |
| nexabank-agents | 5 minutes | 12 hours (field shifts) |
| nexabank-partners | 5 minutes | 1 hour |

## mTLS binding

For nexabank-agents and nexabank-partners, enable **X.509 Client Certificate User Identity Provider** in the realm authentication flow and bind the certificate CN to the Keycloak username attribute.
