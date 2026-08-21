// Real load test against the real ALB - not a synthetic benchmark. Exercises
// the exact path api's HPA (helm/kubeforge/templates/hpa.yaml) is watching:
// api pod CPU. Each iteration does a real Postgres write (POST /api/tasks,
// which also publishes to RabbitMQ and gets picked up by worker) and a real
// Postgres read (GET /api/tasks) - not a static endpoint, so this reflects
// actual request cost, not an artificially cheap health-check ping.
//
// Staged ramp rather than a flat load level on purpose: a flat 100 VUs from
// second zero doesn't tell you AT WHAT POINT scaling kicks in, just whether
// it eventually does. Ramping up gradually is what makes it possible to
// correlate "requests/sec crossed X" with "HPA scaled to Y pods" in the
// results afterward - see docs/autoscaling.md for how to read this
// alongside `kubectl get hpa -w` output collected during the same run.
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 20 },   // baseline - should NOT trigger scaling
    { duration: '3m', target: 50 },   // likely crosses the 70% CPU target on 2 starting replicas
    { duration: '4m', target: 100 },  // sustained - enough time for a Cluster Autoscaler node addition to complete if pods go Pending
    { duration: '2m', target: 0 },    // ramp down - also worth watching: does HPA scale back down, and how long does it take?
  ],
  thresholds: {
    // Not a pass/fail gate on infra scaling itself (that's the whole point
    // of the test), just a sanity check that the app doesn't fall over
    // outright under load.
    http_req_failed: ['rate<0.05'],
  },
};

const BASE_URL = __ENV.BASE_URL;

export default function () {
  if (!BASE_URL) {
    throw new Error('Set -e BASE_URL=http://<your-alb-hostname> when running this script');
  }

  const createRes = http.post(
    `${BASE_URL}/api/tasks`,
    JSON.stringify({ title: `load-test-${__VU}-${__ITER}-${Date.now()}` }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(createRes, { 'create status is 201': (r) => r.status === 201 });

  const listRes = http.get(`${BASE_URL}/api/tasks`);
  check(listRes, { 'list status is 200': (r) => r.status === 200 });

  sleep(1);
}
