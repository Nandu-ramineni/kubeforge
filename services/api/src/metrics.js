import client from 'prom-client';
import config from './config.js';

const register = new client.Registry();
register.setDefaultLabels({ service: config.serviceName });
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
});
register.registerMetric(httpRequestDuration);

const tasksCreatedTotal = new client.Counter({
  name: 'kubeforge_tasks_created_total',
  help: 'Total number of tasks created',
});
register.registerMetric(tasksCreatedTotal);

export { register, httpRequestDuration, tasksCreatedTotal };
