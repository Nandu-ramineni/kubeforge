import amqplib from 'amqplib';
import config from './config.js';
import logger from './logger.js';

let connection;
let channel;

export async function initQueue() {
  // amqplib picks TLS automatically from the amqps:// scheme used by managed
  // brokers (Amazon MQ, CloudAMQP) - no separate TLS config needed here.
  connection = await amqplib.connect(config.rabbitmq.url);
  connection.on('error', (err) => logger.error({ err }, 'RabbitMQ connection error'));
  connection.on('close', () => logger.warn('RabbitMQ connection closed'));

  channel = await connection.createChannel();
  await channel.assertQueue(config.rabbitmq.taskQueue, { durable: true });

  logger.info({ queue: config.rabbitmq.taskQueue }, 'RabbitMQ connected and queue asserted');
}

export function publishTaskCreated(taskId) {
  if (!channel) throw new Error('Queue channel not initialized');
  const payload = Buffer.from(JSON.stringify({ taskId }));
  channel.sendToQueue(config.rabbitmq.taskQueue, payload, { persistent: true });
}

export async function checkQueueHealth() {
  if (!connection || !channel) throw new Error('Queue not connected');
}
