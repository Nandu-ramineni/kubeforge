import client from 'prom-client';
import config from './config.js';

const register = new client.Registry();
register.setDefaultLabels({ service: config.serviceName });
client.collectDefaultMetrics({ register });

const tasksProcessedTotal = new client.Counter({
  name: 'kubeforge_tasks_processed_total',
  help: 'Total number of tasks successfully processed',
});
register.registerMetric(tasksProcessedTotal);

const tasksFailedTotal = new client.Counter({
  name: 'kubeforge_tasks_failed_total',
  help: 'Total number of tasks that failed processing',
});
register.registerMetric(tasksFailedTotal);

const taskProcessingDuration = new client.Histogram({
  name: 'kubeforge_task_processing_duration_seconds',
  help: 'Time taken to process a single task',
  buckets: [0.1, 0.5, 1, 2, 5, 10],
});
register.registerMetric(taskProcessingDuration);

export { register, tasksProcessedTotal, tasksFailedTotal, taskProcessingDuration };
