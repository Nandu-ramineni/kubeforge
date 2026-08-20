import pg from 'pg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import config from './config.js';
import logger from './logger.js';

const { Pool } = pg;

// See services/api/src/db.js for the full explanation of why this exists.
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RDS_CA_BUNDLE_PATH = path.join(__dirname, '..', 'rds-ca-bundle.pem');

const pool = new Pool({
  connectionString: config.db.connectionString,
  ssl: config.db.ssl
    ? { rejectUnauthorized: true, ca: fs.readFileSync(RDS_CA_BUNDLE_PATH) }
    : false,
});

pool.on('error', (err) => logger.error({ err }, 'Unexpected Postgres pool error'));

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
  logger.info('Postgres connected');
}

export async function checkDbHealth() {
  await pool.query('SELECT 1');
}

export async function markTaskStatus(taskId, status) {
  await pool.query('UPDATE tasks SET status = $1, updated_at = now() WHERE id = $2', [status, taskId]);
}

export async function getTask(taskId) {
  const result = await pool.query('SELECT * FROM tasks WHERE id = $1', [taskId]);
  return result.rows[0] || null;
}

export { pool };
