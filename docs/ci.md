# Phase 7 — GitHub Actions CI

This pipeline stops at pushing images to ECR. It does **not** deploy
anything - that's Phase 8 (Argo CD / GitOps), which watches ECR/the GitOps
repo and syncs the cluster independently, rather than CI reaching into the
cluster directly.

## Pipeline shape

```
push/PR to main
      │
      ├── lint-and-test (api, worker, frontend, in parallel)
      ├── security-scan  (npm audit, high/critical only)
      └── gitleaks        (secret scanning across full history)
                      │
                      ▼  (only on push to main, not PRs)
            build-scan-push (api, worker, frontend, in parallel)
              build → Trivy scan → push to ECR (tag: full commit SHA)
```

`lint-and-test`, `security-scan`, and `gitleaks` all run on **both** pushes
and pull requests - fast feedback before merge. `build-scan-push` only runs
on an actual push to `main`, and only after all three of the above pass.

## One-time setup: GitHub repository variables

The workflow needs to know which AWS role to assume (Phase 5's
`github_actions_role_arn` output) and which region. These are **repository
variables**, not secrets - an IAM role ARN isn't sensitive on its own (the
trust policy is what actually restricts who can assume it), so it doesn't
need secret-level handling.

1. Get the value:
   ```bash
   cd infrastructure/terraform/environments/dev
   terraform output -raw github_actions_role_arn
   ```
2. GitHub repo → **Settings** → **Secrets and variables** → **Actions** →
   **Variables** tab → **New repository variable**:
   - `AWS_ROLE_ARN` = the ARN from step 1
   - `AWS_REGION` = `us-east-1`

No AWS access keys anywhere - the workflow authenticates via OIDC
(`id-token: write` permission, scoped to only the `build-scan-push` job,
nothing else).

## Local testing before relying on CI

Every check the pipeline runs can be run identically on your own machine
first:
```bash
cd services/api    # or worker, or frontend
npm run lint
npm test
npm audit --audit-level=high
```
All three passed cleanly against the current dependency trees as of this
phase (0 vulnerabilities across all three services) - if `npm audit` ever
fails after adding a new dependency later, that's the pipeline doing exactly
its job, not a bug in the pipeline.

## Why `--env-file` instead of setting env vars in the npm script itself

`services/*/package.json`'s `test` script uses
`node --env-file=.env.test --test` rather than something like
`RABBITMQ_URL=... node --test`. The inline-env-var-before-command syntax is
bash-specific and breaks on Windows outside Git Bash (npm scripts don't
necessarily run under the shell you're typing into) - `--env-file` is parsed
by Node itself, so it works identically everywhere. `.env.test` files are
committed on purpose (dummy values only) - they exist so `config.js`'s
fail-fast RABBITMQ_URL check (Phase 3) doesn't block every test run that
imports it transitively.

## Why the ECR push can't silently collide with itself

ECR's repos are `IMMUTABLE` tag mutability (Phase 5) and every image is
tagged with the full commit SHA, never `:latest`. Re-running the workflow
for a commit that already pushed successfully will fail at the `docker push`
step - that's the immutability policy working as designed, not a bug. A new
commit (even an empty one) is what triggers a new, distinct tag.
