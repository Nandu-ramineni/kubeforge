import config from './config.js';
import logger from './logger.js';
import { initDb, markTaskStatus, getTask } from './db.js';
import { initRedis, invalidateTask } from './redis.js';
import { initQueue, consumeTasks } from './queue.js';
import startHealthServer from './healthServer.js';
import { tasksProcessedTotal, tasksFailedTotal, taskProcessingDuration } from './metrics.js';

async function processTask({ taskId }) {
  const endTimer = taskProcessingDuration.startTimer();
  logger.info({ taskId }, 'Processing task');

  const task = await getTask(taskId);
  if (!task) {
    logger.warn({ taskId }, 'Task not found, skipping');
    endTimer();
    return;
  }

  const workMs = 500 + Math.floor(Math.random() * 1500);
  await new Promise((resolve) => setTimeout(resolve, workMs));

  await markTaskStatus(taskId, 'completed');
  await invalidateTask(taskId);

  tasksProcessedTotal.inc();
  endTimer();
  logger.info({ taskId, workMs }, 'Task completed');
}

async function main() {
  await initDb();
  await initRedis();
  await initQueue();

  const healthServer = startHealthServer(config.healthPort);

  consumeTasks(async (payload) => {
    try {
      await processTask(payload);
    } catch (err) {
      tasksFailedTotal.inc();
      throw err;
    }
  });

  logger.info('Worker started, waiting for tasks');

  process.on('SIGTERM', () => {
    logger.info('SIGTERM received, shutting down worker');
    healthServer.close(() => process.exit(0));
  });
}

main().catch((err) => {
  logger.error({ err }, 'Fatal error during worker startup');
  process.exit(1);
});
