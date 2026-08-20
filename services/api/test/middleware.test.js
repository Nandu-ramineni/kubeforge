import { test } from 'node:test';
import assert from 'node:assert/strict';
import requestId from '../src/middleware/requestId.js';
import errorHandler from '../src/middleware/errorHandler.js';

test('requestId generates a new id when none is provided', () => {
  const req = { headers: {} };
  const headers = {};
  const res = { setHeader: (k, v) => { headers[k] = v; } };
  let nextCalled = false;

  requestId(req, res, () => { nextCalled = true; });

  assert.ok(req.id, 'req.id should be set');
  assert.equal(headers['x-request-id'], req.id);
  assert.ok(nextCalled, 'next() should have been called');
});

test('requestId preserves an existing x-request-id header instead of overwriting it', () => {
  const req = { headers: { 'x-request-id': 'existing-id-123' } };
  const headers = {};
  const res = { setHeader: (k, v) => { headers[k] = v; } };

  requestId(req, res, () => {});

  assert.equal(req.id, 'existing-id-123');
  assert.equal(headers['x-request-id'], 'existing-id-123');
});

test('errorHandler defaults to 500 with a generic message for unexpected errors', () => {
  const req = { id: 'abc', path: '/x' };
  let statusCode, body;
  const res = {
    status(code) { statusCode = code; return this; },
    json(payload) { body = payload; },
  };

  errorHandler(new Error('something broke internally'), req, res, () => {});

  assert.equal(statusCode, 500);
  assert.equal(body.error, 'Internal server error');
  assert.equal(body.requestId, 'abc');
});

test('errorHandler respects a custom status and surfaces its message', () => {
  const req = { id: 'abc', path: '/x' };
  let statusCode, body;
  const res = {
    status(code) { statusCode = code; return this; },
    json(payload) { body = payload; },
  };
  const err = new Error('title is required and must be a string');
  err.status = 400;

  errorHandler(err, req, res, () => {});

  assert.equal(statusCode, 400);
  assert.equal(body.error, 'title is required and must be a string');
});
