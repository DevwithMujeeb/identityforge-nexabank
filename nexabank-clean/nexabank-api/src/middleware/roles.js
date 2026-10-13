'use strict';

/**
 * roles.js
 * Checks that req.user has at least one of the allowed Keycloak realm roles.
 * Keycloak encodes realm roles under realm_access.roles.
 */

const logger = require('../utils/logger');

function rolesMiddleware(allowedRoles) {
  return (req, res, next) => {
    const userRoles = req.user?.realm_access?.roles || [];
    const hasRole = allowedRoles.some(role => userRoles.includes(role));

    if (!hasRole) {
      logger.warn({
        message: 'Access denied: insufficient role',
        userId: req.user?.sub,
        userRoles,
        requiredOneOf: allowedRoles,
        path: req.path
      });
      return res.status(403).json({
        error: 'Forbidden',
        requiredOneOf: allowedRoles,
        userRoles
      });
    }

    next();
  };
}

module.exports = { rolesMiddleware };
