import express from 'express';
import pinoHttp from 'pino-http';
import config from './config.js';
import logger from './logger.js';
import requestId from './middleware/requestId.js';
import errorHandler from './middleware/errorHandler.js';
import healthRoutes from './routes/health.js';
import taskRoutes from './routes/tasks.js';
import { initDb } from './db.js';
import { initRedis } from './redis.js';
import { initQueue } from './queue.js';
import { register } from './metrics.js';

async function main() {
  const app = express();

  app.use(requestId);
  app.use(
    pinoHttp({
      logger,
      genReqId: (req) => req.id,
      customLogLevel: (req, res, err) => {
        if (err || res.statusCode >= 500) return 'error';
        if (res.statusCode >= 400) return 'warn';
        return 'info';
      },
    })
  );
  app.use(express.json());

  // Mounted under /api for tasks (AWS's ALB Ingress Controller, used on real
  // EKS from Phase 6 on, has no rewrite capability like nginx-ingress's
  // rewrite-target - it forwards paths exactly as received - so the route
  // itself matches the public path scheme rather than depending on an
  // ingress-controller-specific rewrite feature).
  //
  // Health is mounted at BOTH paths:
  //   /health      - unprefixed, used by k8s probes AND the ALB target group
  //                  health check. A single ALB Ingress shares one health
  //                  check path across every backend service by default, so
  //                  keeping this unprefixed matches frontend's own
  //                  /health/live exactly - one Ingress annotation covers
  //                  both backends without separate Ingress objects.
  //   /api/health  - prefixed, so curl/humans hitting the public gateway see
  //                  a consistent /api/* surface alongside /api/tasks, even
  //                  though it's the same router mounted twice internally.
  app.use('/health', healthRoutes);
  app.use('/api/health', healthRoutes);
  app.use('/api/tasks', taskRoutes);

  app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  app.use(errorHandler);

  await initDb();
  await initRedis();
  await initQueue();

  const server = app.listen(config.port, () => {
    logger.info({ port: config.port }, 'KubeForge API listening');
  });

  process.on('SIGTERM', () => {
    logger.info('SIGTERM received, closing server');
    server.close(() => process.exit(0));
  });
}

main().catch((err) => {
  logger.error({ err }, 'Fatal error during API startup');
  process.exit(1);
});
