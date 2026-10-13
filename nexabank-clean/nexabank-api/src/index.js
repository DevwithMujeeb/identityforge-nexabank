'use strict';

const express = require('express');
const helmet = require('helmet');
const morgan = require('morgan');

const { authMiddleware } = require('./middleware/auth');
const { mtlsMiddleware } = require('./middleware/mtls');
const { rolesMiddleware } = require('./middleware/roles');
const { auditMiddleware } = require('./middleware/audit');
const logger = require('./utils/logger');

const transactionsRouter = require('./routes/transactions');
const agentsRouter = require('./routes/agents');
const partnersRouter = require('./routes/partners');
const healthRouter = require('./routes/health');

const app = express();
const PORT = process.env.PORT || 3000;

// Security headers
app.use(helmet());
app.use(express.json({ limit: '1mb' }));
app.use(morgan('combined'));

// mTLS validation (applied to agent and partner routes)
app.use('/api/agents', mtlsMiddleware);
app.use('/api/partners', mtlsMiddleware);

// Audit all API calls
app.use('/api', auditMiddleware);

// Auth: validate Keycloak JWT on all protected routes
app.use('/api', authMiddleware);

// Role enforcement per route group
app.use('/api/transactions', rolesMiddleware(['staff', 'agent', 'partner']));
app.use('/api/agents', rolesMiddleware(['agent', 'admin']));
app.use('/api/partners', rolesMiddleware(['partner', 'admin']));

// Routes
app.use('/health', healthRouter);
app.use('/api/transactions', transactionsRouter);
app.use('/api/agents', agentsRouter);
app.use('/api/partners', partnersRouter);

// 404
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Error handler
app.use((err, req, res, next) => {
  logger.error({ message: err.message, stack: err.stack, path: req.path });
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

app.listen(PORT, () => {
  logger.info(`NexaBank API running on port ${PORT}`);
});

module.exports = app;
