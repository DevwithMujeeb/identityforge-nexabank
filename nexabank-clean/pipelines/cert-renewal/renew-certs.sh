#!/usr/bin/env bash
# =============================================================================
# renew-certs.sh
# NexaBank IdentityForge — Automated Certificate Renewal
# =============================================================================
# Runs as a cron job (e.g. daily at 02:00) to renew agent and partner certs
# expiring within the RENEWAL_THRESHOLD_DAYS window.
#
# Usage: ./renew-certs.sh [--dry-run]
#
# Prerequisites: step CLI, curl, jq
# =============================================================================

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

CA_URL="${CA_URL:-https://ca.nexabank.internal}"
CERTS_BASE_DIR="${CERTS_BASE_DIR:-./certs}"
RENEWAL_THRESHOLD_DAYS="${RENEWAL_THRESHOLD_DAYS:-30}"
LOG_FILE="./logs/cert-renewal.log"

mkdir -p "$(dirname "${LOG_FILE}")"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "${LOG_FILE}"
}

log "Starting cert renewal scan. Threshold=${RENEWAL_THRESHOLD_DAYS} days. DryRun=${DRY_RUN}"

# Find all certs under CERTS_BASE_DIR
find "${CERTS_BASE_DIR}" -name "*.crt" | while read -r CERT_PATH; do
  EXPIRY=$(openssl x509 -enddate -noout -in "${CERT_PATH}" 2>/dev/null | cut -d= -f2)
  if [[ -z "${EXPIRY}" ]]; then
    log "SKIP ${CERT_PATH}: could not parse expiry"
    continue
  fi

  EXPIRY_EPOCH=$(date -d "${EXPIRY}" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "${EXPIRY}" +%s 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
  SUBJECT=$(openssl x509 -subject -noout -in "${CERT_PATH}" 2>/dev/null | sed 's/subject=//')

  if (( DAYS_LEFT <= RENEWAL_THRESHOLD_DAYS )); then
    log "RENEW ${CERT_PATH} | Subject: ${SUBJECT} | Days left: ${DAYS_LEFT}"
    if [[ "${DRY_RUN}" == "false" ]]; then
      KEY_PATH="${CERT_PATH%.crt}.key"
      if [[ ! -f "${KEY_PATH}" ]]; then
        log "ERROR: Key not found at ${KEY_PATH}. Skipping."
        continue
      fi

      # TODO (mentee): configure Smallstep provisioner credentials
      # step ca renew "${CERT_PATH}" "${KEY_PATH}" \
      #   --ca-url "${CA_URL}" \
      #   --root ./certs/ca.crt \
      #   --provisioner nexabank-agents \
      #   --provisioner-password-file ./secrets/provisioner.pass \
      #   --force

      log "WARN: Renewal stubbed for ${CERT_PATH}. Implement step ca renew above."
    else
      log "[DRY-RUN] Would renew ${CERT_PATH}"
    fi
  else
    log "OK ${CERT_PATH} | Days left: ${DAYS_LEFT}"
  fi
done

log "Cert renewal scan complete."
