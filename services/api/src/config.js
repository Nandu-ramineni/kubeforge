import 'dotenv/config';

// RABBITMQ_URL has no local fallback on purpose: KubeForge uses a managed
// cloud RabbitMQ broker (e.g. Amazon MQ for RabbitMQ, or CloudAMQP) rather
// than a self-hosted RabbitMQ container/pod, so there is no meaningful
// "localhost" default to fall back to. Failing fast here at startup with a
// clear message beats a confusing ECONNREFUSED five seconds later.
const rabbitmqUrl = process.env.RABBITMQ_URL;
if (!rabbitmqUrl) {
  throw new Error(
    'RABBITMQ_URL is required and must point to your managed RabbitMQ broker ' +
      '(e.g. amqps://user:pass@your-broker-host/vhost). There is no localhost default.'
  );
}

export default {
  serviceName: 'api',
  port: parseInt(process.env.PORT || '3000', 10),
  logLevel: process.env.LOG_LEVEL || 'info',

  db: {
    connectionString:
      process.env.DATABASE_URL ||
      `postgres://${process.env.PGUSER || 'kubeforge'}:${process.env.PGPASSWORD || 'kubeforge'}@${
        process.env.PGHOST || 'localhost'
      }:${process.env.PGPORT || '5432'}/${process.env.PGDATABASE || 'kubeforge'}`,
    // RDS enforces SSL/TLS by default (Postgres rejects the connection
    // outright with "no encryption" otherwise - this is exactly what
    // happened the first time this connected to real RDS). Local/kind
    // Postgres has no TLS listener at all, so this defaults to false and
    // only gets turned on via DB_SSL=true in k8s/eks's ConfigMap, where the
    // target is genuinely RDS.
    ssl: process.env.DB_SSL === 'true',
  },

  redis: {
    url: process.env.REDIS_URL || 'redis://localhost:6379',
    taskCacheTtlSeconds: parseInt(process.env.TASK_CACHE_TTL_SECONDS || '30', 10),
  },

  rabbitmq: {
    url: rabbitmqUrl,
    taskQueue: process.env.TASK_QUEUE_NAME || 'tasks.process',
  },
};
