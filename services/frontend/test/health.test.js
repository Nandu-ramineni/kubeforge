import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

// The frontend has zero external dependencies (no DB, no Redis, no queue),
// so unlike api/worker there's nothing to fail-fast on and nothing to mock -
// the real server can just be started and hit over real HTTP. This is a
// genuine integration test, not a mock-heavy unit test.
test('frontend serves /health/live and the static page for real', async () => {
  const port = 34567;
  const proc = spawn(process.execPath, ['src/index.js'], {
    env: { ...process.env, PORT: String(port) },
  });

  const startupError = new Promise((_, reject) => {
    proc.on('error', reject);
    proc.on('exit', (code) => {
      if (code !== null && code !== 0) reject(new Error(`server exited early with code ${code}`));
    });
  });

  try {
    // Poll instead of a fixed sleep - faster on a healthy start, more
    // tolerant on a slow CI runner than a single guessed delay would be.
    const ready = (async () => {
      for (let i = 0; i < 20; i++) {
        try {
          const res = await fetch(`http://127.0.0.1:${port}/health/live`);
          if (res.ok) return;
        } catch {
          // not up yet, keep polling
        }
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
      throw new Error('server did not become ready in time');
    })();

    await Promise.race([ready, startupError]);

    const health = await fetch(`http://127.0.0.1:${port}/health/live`);
    assert.equal(health.status, 200);
    const healthBody = await health.json();
    assert.equal(healthBody.status, 'ok');

    const page = await fetch(`http://127.0.0.1:${port}/`);
    assert.equal(page.status, 200);
    const html = await page.text();
    assert.match(html, /KubeForge/);

    const missing = await fetch(`http://127.0.0.1:${port}/does-not-exist`);
    assert.equal(missing.status, 404);
  } finally {
    proc.kill();
  }
});
