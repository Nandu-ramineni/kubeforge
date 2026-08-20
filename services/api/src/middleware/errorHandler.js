import logger from '../logger.js';

export default function errorHandler(err, req, res, next) {
  logger.error({ err, requestId: req.id, path: req.path }, err.message || 'Unhandled error');

  const status = err.status || 500;
  res.status(status).json({
    error: status === 500 ? 'Internal server error' : err.message,
    requestId: req.id,
  });
}
