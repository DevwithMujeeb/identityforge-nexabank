'use strict';

/**
 * partners.js
 * Partner microfinance bank endpoints. Requires mTLS + nexabank-partners realm JWT.
 * 12 partner MFBs each have a unique client cert and Keycloak client credential.
 *
 * DELIBERATE CHALLENGE: partner token scope is not validated per-partner.
 * Mentees must add partner_id claim enforcement so MFB-A cannot query MFB-B's data.
 */

const express = require('express');
const axios = require('axios');
const logger = require('../utils/logger');
const router = express.Router();

// GET /api/partners/me — partner identity
router.get('/me', (req, res) => {
  res.json({
    partnerId: req.user.partner_id || req.user.sub,   // custom Keycloak claim
    certSubject: req.clientCertSubject || null,
    realm: req.realm,
    roles: req.user.realm_access?.roles || [],
    mfbCode: req.user.mfb_code || null               // custom Keycloak attribute
  });
});

// GET /api/partners/:partnerId/accounts — list partner account pool
router.get('/:partnerId/accounts', async (req, res) => {
  const { partnerId } = req.params;

  // CHALLENGE: verify req.user.partner_id === partnerId before serving data
  // Current stub does not enforce this — mentees must fix it
  logger.warn({
    event: 'partner_account_query',
    requestingPartner: req.user.partner_id,
    targetPartner: partnerId,
    note: 'partner_id isolation not yet enforced'
  });

  // TODO (mentee challenge): query PostgreSQL for real partner account data
  res.json({
    partnerId,
    accounts: [],
    note: 'Stub — connect to PostgreSQL and enforce partner_id isolation'
  });
});

// POST /api/partners/bulk-revoke — revoke all sessions for a partner (e.g. after breach)
router.post('/bulk-revoke', async (req, res) => {
  const { partnerId, reason } = req.body;
  if (!partnerId) return res.status(400).json({ error: 'partnerId is required' });

  const keycloakUrl = process.env.KEYCLOAK_URL || 'http://localhost:8080';
  const adminToken = req.headers['x-admin-token'];

  logger.info({ event: 'partner_bulk_revoke_initiated', partnerId, reason, initiatedBy: req.user.sub });

  try {
    // TODO (mentee challenge): list all active sessions for the partner client in Keycloak
    // and revoke them; also submit cert revocation for partner's client cert to Smallstep CA
    await axios.post(
      `${keycloakUrl}/admin/realms/nexabank-partners/clients/${partnerId}/session-count`,
      {},
      { headers: { Authorization: `Bearer ${adminToken}` } }
    );

    res.json({ status: 'revoke_initiated', partnerId });
  } catch (err) {
    logger.error({ event: 'partner_bulk_revoke_failed', partnerId, error: err.message });
    res.status(500).json({ error: 'Revocation failed', detail: err.message });
  }
});

module.exports = router;
