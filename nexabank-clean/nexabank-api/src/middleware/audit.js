'use strict';

/**
 * audit.js
 * Writes a structured audit log entry for every API request.
 * Captures: timestamp, user sub, realm, IP, method, path, status, latency.
 */

const logger = require('../utils/logger');

function auditMiddleware(req, res, next) {
  const start = Date.now();

  res.on('finish', () => {
    logger.info({
      event: 'api_request',
      timestamp: new Date().toISOString(),
      userId: req.user?.sub || 'unauthenticated',
      realm: req.realm || 'unknown',
      clientCert: req.clientCertSubject || null,
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      latencyMs: Date.now() - start,
      ip: req.ip,
      userAgent: req.headers['user-agent'] || null
    });
  });

  next();
}

module.exports = { auditMiddleware };
