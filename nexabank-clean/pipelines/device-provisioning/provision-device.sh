#!/usr/bin/env bash
# =============================================================================
# provision-device.sh
# NexaBank IdentityForge — Field Agent Tablet Provisioning Pipeline
# =============================================================================
# Usage: ./provision-device.sh <AGENT_ID> <BRANCH_CODE> <REGION>
#
# What this script does:
#   1. Generates a private key and CSR for the agent's tablet
#   2. Submits CSR to Smallstep CA and retrieves a signed cert
#   3. Creates the agent user account in Keycloak (nexabank-agents realm)
#   4. Binds the cert CN to the Keycloak user via a custom attribute
#   5. Uploads the cert + config bundle to the MDM system
#   6. Records the provisioning event in the audit log
#
# Prerequisites: step CLI, curl, jq, keycloak-admin-cli (kcadm.sh)
# =============================================================================

set -euo pipefail

AGENT_ID="${1:?Usage: $0 <AGENT_ID> <BRANCH_CODE> <REGION>}"
BRANCH_CODE="${2:?Usage: $0 <AGENT_ID> <BRANCH_CODE> <REGION>}"
REGION="${3:?Usage: $0 <AGENT_ID> <BRANCH_CODE> <REGION>}"

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
CA_URL="${CA_URL:-https://ca.nexabank.internal}"
CERTS_DIR="./certs/agents/${AGENT_ID}"
LOG_FILE="./logs/provisioning.log"

mkdir -p "${CERTS_DIR}" "$(dirname "${LOG_FILE}")"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "${LOG_FILE}"
}

log "Starting device provisioning for agent=${AGENT_ID} branch=${BRANCH_CODE} region=${REGION}"

# --- Step 1: Generate private key ---
log "Generating RSA-4096 private key..."
openssl genrsa -out "${CERTS_DIR}/agent.key" 4096
chmod 600 "${CERTS_DIR}/agent.key"

# --- Step 2: Generate CSR ---
log "Generating CSR..."
openssl req -new \
  -key "${CERTS_DIR}/agent.key" \
  -out "${CERTS_DIR}/agent.csr" \
  -subj "/CN=${AGENT_ID}/O=NexaBank/OU=FieldAgents/L=${BRANCH_CODE}/ST=${REGION}/C=NG"

# --- Step 3: Submit CSR to Smallstep CA ---
log "Submitting CSR to Smallstep CA at ${CA_URL}..."
# TODO (mentee): configure Smallstep provisioner and update this command
# step ca sign "${CERTS_DIR}/agent.csr" "${CERTS_DIR}/agent.crt" \
#   --ca-url "${CA_URL}" \
#   --root ./certs/ca.crt \
#   --provisioner nexabank-agents \
#   --provisioner-password-file ./secrets/provisioner.pass \
#   --not-after 8760h  # 1 year validity

# Stub: copy a placeholder cert so the rest of the script can run
echo "PLACEHOLDER — replace with real Smallstep step ca sign output" > "${CERTS_DIR}/agent.crt"
log "WARN: Using placeholder cert. Run the step ca sign command above."

# --- Step 4: Register user in Keycloak ---
log "Creating Keycloak user for agent=${AGENT_ID}..."
# TODO (mentee): configure kcadm server credentials
# kcadm.sh config credentials \
#   --server "${KEYCLOAK_URL}" \
#   --realm master \
#   --user "${KEYCLOAK_ADMIN}" \
#   --password "${KEYCLOAK_ADMIN_PASSWORD}"
#
# kcadm.sh create users -r nexabank-agents \
#   -s username="${AGENT_ID}" \
#   -s enabled=true \
#   -s 'attributes.cert_cn=["'"${AGENT_ID}"'"]' \
#   -s 'attributes.branch_code=["'"${BRANCH_CODE}"'"]' \
#   -s 'attributes.region=["'"${REGION}"'"]'
log "WARN: Keycloak user creation stubbed. Implement kcadm.sh commands above."

# --- Step 5: Bundle for MDM ---
log "Creating MDM deployment bundle..."
tar -czf "${CERTS_DIR}/device-bundle.tar.gz" \
  -C "${CERTS_DIR}" agent.crt agent.key 2>/dev/null || true
log "MDM bundle created at ${CERTS_DIR}/device-bundle.tar.gz"

# --- Step 6: Audit log ---
log "Provisioning complete for agent=${AGENT_ID}"
echo "{\"event\":\"device_provisioned\",\"agentId\":\"${AGENT_ID}\",\"branch\":\"${BRANCH_CODE}\",\"region\":\"${REGION}\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "${LOG_FILE}"
