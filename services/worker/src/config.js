import 'dotenv/config';

// Same as the API: RabbitMQ is a managed cloud broker, so there is no
// localhost fallback to reach for. Fail fast and loudly if it's missing.
const rabbitmqUrl = process.env.RABBITMQ_URL;
if (!rabbitmqUrl) {
  throw new Error(
    'RABBITMQ_URL is required and must point to your managed RabbitMQ broker ' +
      '(e.g. amqps://user:pass@your-broker-host/vhost). There is no localhost default.'
  );
}

export default {
  serviceName: 'worker',
  healthPort: parseInt(process.env.HEALTH_PORT || '3001', 10),
  logLevel: process.env.LOG_LEVEL || 'info',

  db: {
    connectionString:
      process.env.DATABASE_URL ||
      `postgres://${process.env.PGUSER || 'kubeforge'}:${process.env.PGPASSWORD || 'kubeforge'}@${
        process.env.PGHOST || 'localhost'
      }:${process.env.PGPORT || '5432'}/${process.env.PGDATABASE || 'kubeforge'}`,
    ssl: process.env.DB_SSL === 'true', // see services/api/src/config.js for why
  },

  redis: {
    url: process.env.REDIS_URL || 'redis://localhost:6379',
  },

  rabbitmq: {
    url: rabbitmqUrl,
    taskQueue: process.env.TASK_QUEUE_NAME || 'tasks.process',
    prefetch: parseInt(process.env.QUEUE_PREFETCH || '5', 10),
  },
};
