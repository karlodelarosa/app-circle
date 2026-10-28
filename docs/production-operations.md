# Production operations

Circles shares SheepCount's canonical Supabase database. SheepCount owns the baseline migration history; this repository must contain or consume that exact history before any Circles migration is applied.

## Migration reconciliation

1. Link only a non-production SheepCount staging project.
2. Import the canonical SheepCount migration files without renaming version prefixes.
3. Run `npm run db:verify:linked`. Any remote-only or local-only version blocks deployment.
4. Run `supabase db push --dry-run --linked`; review the SQL and require an empty unexpected schema diff.
5. Create a clean staging project from the canonical baseline plus Circles migrations. Run both SQL files under `supabase/tests/`.

Never repair production migration history simply to make the version table green. Resolve the canonical source with the SheepCount database owner.

## Backup, restore, and rollback

Before a migration release, create a custom-format `pg_dump`, validate it with `pg_restore --list`, and restore it into an isolated database. Validate row counts and the two SQL authorization suites against the restored database. Record the backup identifier, release SHA, operator, restore duration, and result.

Database changes use expand/contract migrations. Application rollback is a Cloudflare Worker version rollback; destructive database contraction happens only after the rollback window closes.

## Protected submissions

Deploy `circle-public-submit` and set these Supabase Edge Function secrets:

- `CIRCLES_ALLOWED_ORIGINS=https://circles.elgchurch.com`
- `CLOUDFLARE_TURNSTILE_SECRET`
- `PUBLIC_RATE_LIMIT_SALT` (at least 32 random bytes)

Set `VITE_TURNSTILE_SITE_KEY` in the Cloudflare build environment. The endpoint fails closed when any server secret is missing. Deploy the function before applying the migration that revokes anonymous RPC execution, then deploy the web client.

## Monitoring and alerts

Monitor `GET /healthz` from at least two regions every minute. Alert after two consecutive failures. Route structured Cloudflare and Supabase function logs to the SheepCount log sink and alert on `auth_failure`, `public_submission_rate_limited`, `public_submission_bot_rejected`, `public_submission_failed`, `member_account_operation_failed`, and database health latency above 1,000 ms. Keep request IDs in incident notes.

Run retention on a schedule by calling `apply_circle_pii_retention(organization_id)` as the service role for each tenant. Review privacy requests and security audit events through SheepCount administration.
