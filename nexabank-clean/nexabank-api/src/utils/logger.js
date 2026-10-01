'use strict';

const { createLogger, format, transports } = require('winston');

const logger = createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: format.combine(
    format.timestamp(),
    format.errors({ stack: true }),
    format.json()
  ),
  transports: [
    new transports.Console(),
    new transports.File({
      filename: process.env.AUDIT_LOG_PATH || '/tmp/nexabank-audit.log',
      level: 'info'
    })
  ]
});

module.exports = logger;
