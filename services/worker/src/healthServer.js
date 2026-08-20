import http from 'http';
import { checkDbHealth } from './db.js';
import { checkRedisHealth } from './redis.js';
import { checkQueueHealth } from './queue.js';
import { register } from './metrics.js';
import logger from './logger.js';

export default function startHealthServer(port) {
  const server = http.createServer(async (req, res) => {
    if (req.url === '/health/live') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ status: 'ok' }));
    }

    if (req.url === '/health/ready') {
      const checks = {};
      let healthy = true;

      try {
        await checkDbHealth();
        checks.database = 'ok';
      } catch {
        checks.database = 'unreachable';
        healthy = false;
      }

      try {
        await checkRedisHealth();
        checks.redis = 'ok';
      } catch {
        checks.redis = 'unreachable';
        healthy = false;
      }

      try {
        await checkQueueHealth();
        checks.rabbitmq = 'ok';
      } catch {
        checks.rabbitmq = 'unreachable';
        healthy = false;
      }

      res.writeHead(healthy ? 200 : 503, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ status: healthy ? 'ok' : 'degraded', checks }));
    }

    if (req.url === '/metrics') {
      res.writeHead(200, { 'Content-Type': register.contentType });
      return res.end(await register.metrics());
    }

    res.writeHead(404);
    res.end();
  });

  server.listen(port, () => {
    logger.info({ port }, 'Worker health server listening');
  });

  return server;
}
