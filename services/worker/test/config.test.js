import { test } from 'node:test';
import assert from 'node:assert/strict';

// '' rather than delete throughout this file - config.js's own
// `import 'dotenv/config'` reads the real .env sitting next to this test
// (which has real values for local dev) and silently restores any key that
// was deleted but not one that's merely set to ''. See
// services/api/test/config.test.js for the full explanation and the
// empirical proof this actually matters, not just theoretical.

test('config throws a clear error when RABBITMQ_URL is missing', async () => {
  process.env.RABBITMQ_URL = '';
  await assert.rejects(
    () => import(`../src/config.js?t=${Date.now()}-${Math.random()}`),
    /RABBITMQ_URL is required/
  );
});

test('config loads successfully once RABBITMQ_URL is set', async () => {
  process.env.RABBITMQ_URL = 'amqps://user:pass@broker.example.com/vhost';
  const mod = await import(`../src/config.js?t=${Date.now()}-${Math.random()}`);
  assert.equal(mod.default.rabbitmq.url, 'amqps://user:pass@broker.example.com/vhost');
});

test('queue prefetch defaults to 5 when QUEUE_PREFETCH is unset', async () => {
  process.env.RABBITMQ_URL = 'amqps://user:pass@broker.example.com/vhost';
  process.env.QUEUE_PREFETCH = ''; // falsy, same effect as unset for the `|| '5'` fallback in config.js
  const mod = await import(`../src/config.js?t=${Date.now()}-${Math.random()}`);
  assert.equal(mod.default.rabbitmq.prefetch, 5);
});

test('queue prefetch respects an explicit QUEUE_PREFETCH value', async () => {
  process.env.RABBITMQ_URL = 'amqps://user:pass@broker.example.com/vhost';
  process.env.QUEUE_PREFETCH = '10';
  const mod = await import(`../src/config.js?t=${Date.now()}-${Math.random()}`);
  assert.equal(mod.default.rabbitmq.prefetch, 10);
  process.env.QUEUE_PREFETCH = ''; // leave a clean, dotenv-proof state
});
