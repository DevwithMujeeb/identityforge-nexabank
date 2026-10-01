'use strict';

/**
 * auth.js
 * Validates Keycloak-issued JWTs using JWKS.
 * Supports all three NexaBank realms: nexabank-staff, nexabank-agents, nexabank-partners.
 */

const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');
const logger = require('../utils/logger');

const KEYCLOAK_URL = process.env.KEYCLOAK_URL || 'http://localhost:8080';

// One JWKS client per realm
const realmClients = {
  'nexabank-staff': jwksClient({
    jwksUri: `${KEYCLOAK_URL}/realms/nexabank-staff/protocol/openid-connect/certs`,
    cache: true,
    rateLimit: true,
    jwksRequestsPerMinute: 10
  }),
  'nexabank-agents': jwksClient({
    jwksUri: `${KEYCLOAK_URL}/realms/nexabank-agents/protocol/openid-connect/certs`,
    cache: true,
    rateLimit: true,
    jwksRequestsPerMinute: 10
  }),
  'nexabank-partners': jwksClient({
    jwksUri: `${KEYCLOAK_URL}/realms/nexabank-partners/protocol/openid-connect/certs`,
    cache: true,
    rateLimit: true,
    jwksRequestsPerMinute: 10
  })
};

function getSigningKey(realm, header, callback) {
  const client = realmClients[realm];
  if (!client) return callback(new Error(`Unknown realm: ${realm}`));
  client.getSigningKey(header.kid, (err, key) => {
    if (err) return callback(err);
    callback(null, key.getPublicKey());
  });
}

/**
 * Extracts realm from the JWT iss claim (e.g. .../realms/nexabank-staff).
 */
function extractRealm(token) {
  try {
    const decoded = jwt.decode(token);
    if (!decoded || !decoded.iss) return null;
    const match = decoded.iss.match(/\/realms\/([^/]+)$/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid Authorization header' });
  }

  const token = authHeader.split(' ')[1];
  const realm = extractRealm(token);

  if (!realm || !realmClients[realm]) {
    return res.status(401).json({ error: 'Unrecognized token realm' });
  }

  jwt.verify(
    token,
    (header, callback) => getSigningKey(realm, header, callback),
    { algorithms: ['RS256'] },
    (err, decoded) => {
      if (err) {
        logger.warn({ message: 'JWT verification failed', error: err.message, realm });
        return res.status(401).json({ error: 'Invalid or expired token' });
      }
      req.user = decoded;
      req.realm = realm;
      next();
    }
  );
}

module.exports = { authMiddleware };
