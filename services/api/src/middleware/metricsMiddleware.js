import { httpRequestDuration } from '../metrics.js';

// This is the piece that was missing since Phase 2: httpRequestDuration was
// defined and registered, but nothing ever called .observe() on it - a
// dashboard querying it would have shown "No data", not real numbers.
//
// The one detail that actually matters here: labeling with req.route.path
// (the matched PATTERN, e.g. "/:id") rather than req.path (the resolved
// URL, e.g. "/api/tasks/8c5cb594-..."). Every distinct task UUID would
// otherwise create its own Prometheus time series - unbounded cardinality
// that grows forever and is a well-known way to quietly degrade or crash a
// Prometheus instance over time. Unmatched routes (404s, including anyone
// probing random paths) collapse to a fixed "unmatched" label for the same
// reason, rather than recording the raw attempted path.
export default function metricsMiddleware(req, res, next) {
  const start = process.hrtime.bigint();

  res.on('finish', () => {
    const durationSeconds = Number(process.hrtime.bigint() - start) / 1e9;
    const route = req.route ? `${req.baseUrl}${req.route.path}` : 'unmatched';

    httpRequestDuration.observe(
      { method: req.method, route, status_code: res.statusCode },
      durationSeconds
    );
  });

  next();
}
