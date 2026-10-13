'use strict';

/**
 * transactions.js
 * Handles financial transaction endpoints.
 * Requires: valid JWT (any NexaBank realm) + at least one of [staff, agent, partner] roles.
 *
 * DELIBERATE CHALLENGE: this route validates realm-specific claims but does not
 * enforce field-level data masking for partner tokens. Mentees must identify and fix this.
 */

const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('../utils/logger');
const router = express.Router();

// POST /api/transactions — initiate a transaction
router.post('/', (req, res) => {
  const { amount, currency, toAccount, description } = req.body;

  if (!amount || !currency || !toAccount) {
    return res.status(400).json({ error: 'amount, currency, and toAccount are required' });
  }

  const transactionId = uuidv4();

  logger.info({
    event: 'transaction_initiated',
    transactionId,
    userId: req.user.sub,
    realm: req.realm,
    amount,
    currency,
    toAccount
  });

  // TODO (mentee challenge): persist to PostgreSQL using the pg pool
  // TODO (mentee challenge): enforce transaction limits per realm
  //   - staff: up to NGN 10,000,000
  //   - agents: up to NGN 500,000
  //   - partners: API-defined per partner agreement

  res.status(202).json({
    transactionId,
    status: 'pending',
    message: 'Transaction accepted for processing'
  });
});

// GET /api/transactions/:id — fetch transaction status
router.get('/:id', (req, res) => {
  const { id } = req.params;

  // TODO (mentee challenge): query PostgreSQL for real transaction data

  res.json({
    transactionId: id,
    status: 'pending',
    note: 'Stub response — connect to PostgreSQL to return real data'
  });
});

module.exports = router;
