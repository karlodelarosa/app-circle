# Tasks: Short Member IDs and Role-Aware Prayer Destinations

## Task 1: Generate short Member IDs

- [x] Generate new IDs from the first word of the first-name field plus four digits.
- [x] Normalize accents/punctuation and use `member` as the fallback.
- [x] Check application links and Supabase Auth for collisions.
- [x] Preserve all existing IDs and password-reset behavior.
- [x] Cover formatting, fallback, and collision retries with focused tests.

## Task 2: Add role-aware prayer destinations

- [x] Add optional `groupId` to `PrayerInput` and validate Circle destinations against accessible groups.
- [x] Keep the active Circle fixed for regular members.
- [x] Show all accessible Circles to leaders and organization administrators.
- [x] Keep organization-wide sharing and omit its Circle id.
- [x] Open a different destination Circle only after successful creation.
- [x] Cover member, leader, success, and failure behavior with tests.

## Task 3: Guidance and specification

- [x] Update the sign-in example to the short Member ID format.
- [x] Document that existing IDs remain valid.
- [x] Update `SPEC-prayer-scope.md` with the role-aware destination rules.

## Task 4: Verify and release

- [x] Full automated test suite passes.
- [x] Production build passes.
- [ ] Database dry-run and authorization smoke checks pass. Blocked by pre-existing remote migration-history drift and unavailable local PostgreSQL; this feature adds no migration.
- [x] Browser accessibility and responsive checks pass for the updated controls and sign-in guidance.
- [x] Member-access Edge Function is deployed.
- [x] Frontend is deployed without unrelated workspace changes.
- [x] Public production smoke check returns HTTP 200 and serves the new `john-4827`, `Choose Circle`, and `Entire organization` assets.
- [ ] Authenticated production creation/sign-in smoke check requires a safe test member account.
