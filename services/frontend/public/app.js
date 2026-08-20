// Relative path, not an absolute URL. The Ingress (kind/nginx locally,
// ALB on real EKS from Phase 6 on) routes path /api/* straight to the api
// Service, and the api service's own routes are mounted at /api/* too - see
// services/api/src/index.js - so no path rewriting is needed anywhere,
// which matters because ALB has no rewrite capability by default. The
// frontend never needs to know the api's real address, there's no CORS to
// configure, and this exact same code works unmodified across every
// environment - only the Ingress backend routing changes.
const API_BASE = '/api';

async function loadTasks() {
  const res = await fetch(`${API_BASE}/tasks`);
  const tasks = await res.json();
  renderTasks(tasks);
}

function renderTasks(tasks) {
  const list = document.getElementById('task-list');
  list.innerHTML = '';
  tasks.forEach((task) => {
    const li = document.createElement('li');
    li.className = `task task--${task.status}`;
    li.textContent = `${task.title} — ${task.status}`;
    list.appendChild(li);
  });
}

document.getElementById('task-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const titleInput = document.getElementById('title');
  const title = titleInput.value.trim();
  if (!title) return;

  await fetch(`${API_BASE}/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title }),
  });

  titleInput.value = '';
  loadTasks();
  setTimeout(loadTasks, 2000); // pick up the worker's async status update
});

loadTasks();
setInterval(loadTasks, 5000);
