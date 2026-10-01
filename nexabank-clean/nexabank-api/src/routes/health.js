'use strict';

const express = require('express');
const router = express.Router();

// GET /health — no auth required; used by Docker HEALTHCHECK and load balancer
router.get('/', (req, res) => {
  res.json({
    status: 'ok',
    service: 'nexabank-api',
    timestamp: new Date().toISOString()
  });
});

module.exports = router;
