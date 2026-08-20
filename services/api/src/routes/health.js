import express from 'express';
import { checkDbHealth } from '../db.js';
import { checkRedisHealth } from '../redis.js';
import { checkQueueHealth } from '../queue.js';

const router = express.Router();

router.get('/live', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

router.get('/ready', async (req, res) => {
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

  res.status(healthy ? 200 : 503).json({ status: healthy ? 'ok' : 'degraded', checks });
});

export default router;
