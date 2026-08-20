import express from 'express';
import { pool } from '../db.js';
import { getCachedTask, cacheTask, invalidateTask } from '../redis.js';
import { publishTaskCreated } from '../queue.js';
import { tasksCreatedTotal } from '../metrics.js';

const router = express.Router();

router.post('/', async (req, res, next) => {
  try {
    const { title, description } = req.body || {};
    if (!title || typeof title !== 'string') {
      return res.status(400).json({ error: 'title is required and must be a string' });
    }

    const result = await pool.query(
      `INSERT INTO tasks (title, description, status) VALUES ($1, $2, 'pending') RETURNING *`,
      [title, description || null]
    );
    const task = result.rows[0];

    publishTaskCreated(task.id);
    tasksCreatedTotal.inc();

    req.log?.info({ taskId: task.id }, 'Task created and queued for processing');
    res.status(201).json(task);
  } catch (err) {
    next(err);
  }
});

router.get('/', async (req, res, next) => {
  try {
    const result = await pool.query('SELECT * FROM tasks ORDER BY created_at DESC LIMIT 100');
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

router.get('/:id', async (req, res, next) => {
  try {
    const { id } = req.params;

    const cached = await getCachedTask(id);
    if (cached) {
      res.setHeader('x-cache', 'HIT');
      return res.json(cached);
    }

    const result = await pool.query('SELECT * FROM tasks WHERE id = $1', [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Task not found' });
    }

    const task = result.rows[0];
    await cacheTask(task);
    res.setHeader('x-cache', 'MISS');
    res.json(task);
  } catch (err) {
    next(err);
  }
});

router.delete('/:id', async (req, res, next) => {
  try {
    const { id } = req.params;
    await pool.query('DELETE FROM tasks WHERE id = $1', [id]);
    await invalidateTask(id);
    res.status(204).send();
  } catch (err) {
    next(err);
  }
});

export default router;
