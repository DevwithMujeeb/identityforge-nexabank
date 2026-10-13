#!/usr/bin/env bash
# =============================================================================
# offboard-agent.sh
# NexaBank IdentityForge — Agent Offboarding Pipeline
# =============================================================================
# SLA: entire pipeline must complete within 30 minutes.
# Triggered by HR system, incident response, or manual admin action.
#
# Usage: ./offboard-agent.sh <AGENT_ID> "<REASON>"
#
# Steps:
#   1. Disable Keycloak account (blocks new logins immediately)
#   2. Revoke all active Keycloak sessions (60-second token revocation SLA)
#   3. Submit cert serial to Smallstep OCSP/CRL for revocation
#   4. Wipe MDM profile from tablet (via MDM API)
#   5. Write final audit event
#
# Prerequisites: kcadm.sh, step CLI, curl, jq
# =============================================================================

set -euo pipefail

AGENT_ID="${1:?Usage: $0 <AGENT_ID> <REASON>}"
REASON="${2:-unspecified}"

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
CA_URL="${CA_URL:-https://ca.nexabank.internal}"
MDM_URL="${MDM_URL:-https://mdm.nexabank.internal}"
LOG_FILE="./logs/offboarding.log"
START_TIME=$(date +%s)

mkdir -p "$(dirname "${LOG_FILE}")"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "${LOG_FILE}"
}

elapsed() {
  echo $(( $(date +%s) - START_TIME ))
}

assert_sla() {
  local MAX_SECONDS="$1"
  local LABEL="$2"
  local ELAPSED
  ELAPSED=$(elapsed)
  if (( ELAPSED > MAX_SECONDS )); then
    log "SLA BREACH: ${LABEL} exceeded ${MAX_SECONDS}s (elapsed: ${ELAPSED}s)"
    exit 1
  fi
  log "SLA OK: ${LABEL} completed in ${ELAPSED}s (max ${MAX_SECONDS}s)"
}

log "=== Offboarding initiated: agent=${AGENT_ID} reason='${REASON}' ==="

# --- Step 1: Disable Keycloak account ---
log "Step 1: Disabling Keycloak account..."
# TODO (mentee): implement
# KC_USER_ID=$(kcadm.sh get users -r nexabank-agents -q username="${AGENT_ID}" | jq -r '.[0].id')
# kcadm.sh update users/"${KC_USER_ID}" -r nexabank-agents -s enabled=false
log "WARN: Keycloak account disable stubbed. Implement kcadm.sh commands above."

# --- Step 2: Revoke all active sessions (60s sub-SLA) ---
log "Step 2: Revoking all active sessions..."
SESSION_START=$(date +%s)
# TODO (mentee): implement
# kcadm.sh delete users/"${KC_USER_ID}"/sessions -r nexabank-agents
SESSION_ELAPSED=$(( $(date +%s) - SESSION_START ))
if (( SESSION_ELAPSED > 60 )); then
  log "SLA BREACH: session revocation took ${SESSION_ELAPSED}s (max 60s)"
fi
log "Session revocation stubbed. Elapsed: ${SESSION_ELAPSED}s"

# --- Step 3: Revoke certificate ---
log "Step 3: Submitting cert revocation to Smallstep CA..."
CERT_PATH="./certs/agents/${AGENT_ID}/agent.crt"
if [[ -f "${CERT_PATH}" ]]; then
  SERIAL=$(openssl x509 -serial -noout -in "${CERT_PATH}" | cut -d= -f2)
  log "Cert serial: ${SERIAL}"
  # TODO (mentee): implement
  # step ca revoke "${SERIAL}" \
  #   --ca-url "${CA_URL}" \
  #   --root ./certs/ca.crt \
  #   --provisioner nexabank-agents \
  #   --provisioner-password-file ./secrets/provisioner.pass \
  #   --reason keyCompromise
  log "WARN: Cert revocation stubbed. Implement step ca revoke above."
else
  log "WARN: No cert found at ${CERT_PATH}. Skipping cert revocation."
fi

# --- Step 4: MDM wipe ---
log "Step 4: Sending MDM wipe command for agent=${AGENT_ID}..."
# TODO (mentee): call MDM API to wipe the agent's tablet profile
# curl -s -X POST "${MDM_URL}/api/devices/${AGENT_ID}/wipe" \
#   -H "Authorization: Bearer ${MDM_TOKEN}" \
#   -H "Content-Type: application/json" \
#   -d '{"reason":"'"${REASON}"'"}'
log "WARN: MDM wipe stubbed. Implement MDM API call above."

# --- Step 5: Final audit event ---
TOTAL_ELAPSED=$(elapsed)
log "=== Offboarding complete: agent=${AGENT_ID} elapsed=${TOTAL_ELAPSED}s ==="
echo "{\"event\":\"agent_offboarded\",\"agentId\":\"${AGENT_ID}\",\"reason\":\"${REASON}\",\"elapsedSeconds\":${TOTAL_ELAPSED},\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "${LOG_FILE}"

if (( TOTAL_ELAPSED > 1800 )); then
  log "SLA BREACH: total offboarding exceeded 30 minutes (${TOTAL_ELAPSED}s)"
  exit 1
else
  log "SLA OK: offboarding completed within 30-minute SLA"
fi
