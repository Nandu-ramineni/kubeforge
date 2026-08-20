import { createClient } from 'redis';
import config from './config.js';
import logger from './logger.js';

const client = createClient({ url: config.redis.url });
client.on('error', (err) => logger.error({ err }, 'Redis client error'));

export async function initRedis() {
  await client.connect();
  logger.info('Redis connected');
}

export async function checkRedisHealth() {
  await client.ping();
}

export async function invalidateTask(taskId) {
  await client.del(`task:${taskId}`);
}

export { client };
