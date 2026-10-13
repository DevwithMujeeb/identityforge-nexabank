'use strict';

/**
 * agents.js
 * Field agent endpoints. Requires mTLS (enforced upstream) + nexabank-agents realm JWT.
 *
 * Agents are the 2,000 field agents with tablets.
 * Each agent's device cert must match their Keycloak account.
 *
 * DELIBERATE CHALLENGE: the device-cert-to-user binding check is stubbed.
 * Mentees must implement it by querying Keycloak's admin API.
 */

const express = require('express');
const axios = require('axios');
const logger = require('../utils/logger');
const router = express.Router();

// GET /api/agents/me — agent profile bound to their cert
router.get('/me', (req, res) => {
  // TODO (mentee challenge): verify clientCertSubject CN matches req.user.sub in Keycloak
  res.json({
    agentId: req.user.sub,
    certSubject: req.clientCertSubject || null,
    realm: req.realm,
    roles: req.user.realm_access?.roles || [],
    branch: req.user.branch_code || null,         // custom Keycloak attribute
    region: req.user.region || null               // custom Keycloak attribute
  });
});

// POST /api/agents/revoke-session — revoke this agent's session tokens
// Must complete within 60 seconds (SLA from capstone brief)
router.post('/revoke-session', async (req, res) => {
  const agentId = req.user.sub;
  const keycloakUrl = process.env.KEYCLOAK_URL || 'http://localhost:8080';
  const adminToken = req.headers['x-admin-token']; // TODO: replace with service account flow

  logger.info({ event: 'agent_session_revoke_requested', agentId });

  try {
    // TODO (mentee challenge): authenticate as Keycloak service account and call:
    // DELETE /admin/realms/nexabank-agents/users/{id}/sessions
    // Measure and assert completion under 60 seconds.
    await axios.delete(
      `${keycloakUrl}/admin/realms/nexabank-agents/users/${agentId}/sessions`,
      { headers: { Authorization: `Bearer ${adminToken}` } }
    );

    logger.info({ event: 'agent_session_revoked', agentId });
    res.json({ status: 'revoked', agentId });
  } catch (err) {
    logger.error({ event: 'agent_session_revoke_failed', agentId, error: err.message });
    res.status(500).json({ error: 'Revocation failed', detail: err.message });
  }
});

// POST /api/agents/offboard — full offboarding (30-min SLA)
router.post('/offboard', async (req, res) => {
  const { agentId, reason } = req.body;
  if (!agentId) return res.status(400).json({ error: 'agentId is required' });

  logger.info({ event: 'agent_offboard_initiated', agentId, reason, initiatedBy: req.user.sub });

  // TODO (mentee challenge): implement full offboarding pipeline:
  // 1. Disable Keycloak account
  // 2. Revoke all active sessions
  // 3. Submit cert revocation request to Smallstep CA
  // 4. Wipe tablet MDM profile (out-of-scope for API, but log intent)
  // 5. Record audit event
  // Assert entire flow completes under 30 minutes.

  res.status(202).json({
    status: 'offboarding_initiated',
    agentId,
    estimatedCompletionMinutes: 30,
    note: 'Stub — implement the offboarding pipeline as described in docs/runbooks/offboarding.md'
  });
});

module.exports = router;
