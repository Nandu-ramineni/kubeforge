import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';

// ES modules have no __dirname/__filename globals - this is the standard
// replacement, derived from import.meta.url instead.
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const port = parseInt(process.env.PORT || '3002', 10);

app.use(express.static(path.join(__dirname, '..', 'public')));

app.get('/health/live', (req, res) => res.status(200).json({ status: 'ok' }));
app.get('/health/ready', (req, res) => res.status(200).json({ status: 'ok' }));

app.listen(port, () => {
  console.log(`KubeForge frontend listening on port ${port}`);
});
