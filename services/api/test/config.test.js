import { test } from 'node:test';
import assert from 'node:assert/strict';

// config.js throws at module-load time if RABBITMQ_URL is missing (this is
// the exact behavior that was manually verified back in Phase 3 - see
// docs/architecture.md's bug log). A cache-busting query string forces a
// fresh module evaluation each import, since ESM otherwise caches by
// specifier and would only run config.js's top-level code once.

test('config throws a clear error when RABBITMQ_URL is missing', async () => {
  // NOT delete - config.js's own `import 'dotenv/config'` reads the real
  // .env file sitting next to this test (which has a real RABBITMQ_URL for
  // local dev), and would silently restore a deleted key from it. dotenv
  // only fills in keys that are genuinely absent from process.env, so
  // setting an empty string survives - and the config.js check treats an
  // empty string as falsy too, so this still exercises the same code path.
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

test('DB_SSL defaults to false when unset (local/kind Postgres has no TLS listener)', async () => {
  process.env.RABBITMQ_URL = 'amqps://user:pass@broker.example.com/vhost';
  // '' not delete - same dotenv-restores-deleted-keys issue as the
  // RABBITMQ_URL test above. '' !== 'true', so config.db.ssl still
  // correctly evaluates to false regardless of what the real .env contains.
  process.env.DB_SSL = '';
  const mod = await import(`../src/config.js?t=${Date.now()}-${Math.random()}`);
  assert.equal(mod.default.db.ssl, false);
});

test('DB_SSL=true is honored (this is what real RDS needs)', async () => {
  process.env.RABBITMQ_URL = 'amqps://user:pass@broker.example.com/vhost';
  process.env.DB_SSL = 'true';
  const mod = await import(`../src/config.js?t=${Date.now()}-${Math.random()}`);
  assert.equal(mod.default.db.ssl, true);
  process.env.DB_SSL = ''; // leave a clean, dotenv-proof state for any test that runs after this one
});
