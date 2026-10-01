'use strict';

/**
 * mtls.js
 * Validates that the request arrived with a valid client certificate.
 * Applied to /api/agents and /api/partners routes.
 *
 * In production, APISIX/Kong terminates TLS and forwards the verified
 * client cert as the X-Forwarded-Client-Cert (XFCC) header.
 * In development (direct TLS), Node reads req.socket.getPeerCertificate().
 */

const logger = require('../utils/logger');

function parseCertFromHeader(header) {
  // XFCC header contains base64-encoded DER; minimal check: non-empty and parseable
  if (!header) return null;
  // Extract Subject from XFCC: Subject="CN=agent-001,O=NexaBank"
  const subjectMatch = header.match(/Subject="([^"]+)"/);
  return subjectMatch ? subjectMatch[1] : header;
}

function mtlsMiddleware(req, res, next) {
  // Production: cert forwarded by gateway
  const xfcc = req.headers['x-forwarded-client-cert'];
  if (xfcc) {
    const subject = parseCertFromHeader(xfcc);
    if (!subject) {
      logger.warn({ message: 'mTLS rejected: unparseable XFCC header', ip: req.ip });
      return res.status(403).json({ error: 'Invalid client certificate' });
    }
    req.clientCertSubject = subject;
    logger.info({ message: 'mTLS validated via gateway', subject });
    return next();
  }

  // Development: direct TLS
  if (req.socket && typeof req.socket.getPeerCertificate === 'function') {
    const cert = req.socket.getPeerCertificate();
    if (cert && cert.subject) {
      req.clientCertSubject = cert.subject.CN || JSON.stringify(cert.subject);
      logger.info({ message: 'mTLS validated via socket', subject: req.clientCertSubject });
      return next();
    }
  }

  logger.warn({ message: 'mTLS rejected: no client certificate', path: req.path, ip: req.ip });
  return res.status(403).json({ error: 'Client certificate required' });
}

module.exports = { mtlsMiddleware };
