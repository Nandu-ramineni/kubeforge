import amqplib from 'amqplib';
import config from './config.js';
import logger from './logger.js';

let connection;
let channel;

export async function initQueue() {
  connection = await amqplib.connect(config.rabbitmq.url);
  connection.on('error', (err) => logger.error({ err }, 'RabbitMQ connection error'));
  connection.on('close', () => logger.warn('RabbitMQ connection closed'));

  channel = await connection.createChannel();
  await channel.assertQueue(config.rabbitmq.taskQueue, { durable: true });
  await channel.prefetch(config.rabbitmq.prefetch);

  logger.info({ queue: config.rabbitmq.taskQueue }, 'RabbitMQ connected and queue asserted');
}

export function consumeTasks(handler) {
  channel.consume(config.rabbitmq.taskQueue, async (msg) => {
    if (!msg) return;
    try {
      const payload = JSON.parse(msg.content.toString());
      await handler(payload);
      channel.ack(msg);
    } catch (err) {
      logger.error({ err }, 'Failed to process task message');
      channel.nack(msg, false, false);
    }
  });
}

export async function checkQueueHealth() {
  if (!connection || !channel) throw new Error('Queue not connected');
}
