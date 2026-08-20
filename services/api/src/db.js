import pg from 'pg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import config from './config.js';
import logger from './logger.js';

const { Pool } = pg;

// Baked into the Docker image at build time - see Dockerfile. My earlier
// assumption that Node's default trusted-root store would cover RDS's
// certificate chain turned out to be wrong (proven by a real
// SELF_SIGNED_CERT_IN_CHAIN failure against real RDS) - explicitly trusting
// AWS's own published CA bundle is what actually works, and still validates
// the certificate properly (rejectUnauthorized: true) rather than disabling
// verification.
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RDS_CA_BUNDLE_PATH = path.join(__dirname, '..', 'rds-ca-bundle.pem');

const pool = new Pool({
  connectionString: config.db.connectionString,
  ssl: config.db.ssl
    ? { rejectUnauthorized: true, ca: fs.readFileSync(RDS_CA_BUNDLE_PATH) }
    : false,
});

pool.on('error', (err) => {
  logger.error({ err }, 'Unexpected Postgres pool error');
});

async function withRetry(fn, { attempts = 5, delayMs = 2000 } = {}) {
  let lastErr;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      logger.warn(
        { attempt, attempts, err: err.message },
        'Postgres connection attempt failed, retrying'
      );
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
  throw lastErr;
}

export async function initDb() {
  await withRetry(() => pool.query('SELECT 1'));

  await pool.query('CREATE EXTENSION IF NOT EXISTS pgcrypto;');
  await pool.query(`
    CREATE TABLE IF NOT EXISTS tasks (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      title TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);

  logger.info('Postgres connected and schema ensured');
}

export async function checkDbHealth() {
  await pool.query('SELECT 1');
}

export { pool };
