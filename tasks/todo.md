# Tasks: Prayer Audience Scope

## Task 1: Add the prayer audience database contract

**Description:** Add an additive Supabase migration that gives prayer requests an explicit audience, preserves existing data, enforces valid Circle/organization destinations, updates authenticated prayer reads, and secures prayer request and prayer-click mutations according to the approved permission matrix.

**Acceptance criteria:**

- [ ] Existing prayer requests become `circle` scoped without changing ids, Circle ids, authors, responses, timestamps, or answered state.
- [ ] New Circle and organization prayers must satisfy scope, destination, person, and organization consistency rules.
- [ ] Database authorization allows only the approved viewers and actors, including author/admin-only answering for organization prayers and no anonymous or cross-organization access.

**Verification:**

- [ ] Migration dry run succeeds: `npx supabase db push --dry-run`
- [ ] Database authorization cases pass through the repository SQL test/smoke workflow.
- [ ] Manual review confirms public RPCs do not include prayer content.

**Dependencies:** None

**Files likely touched:**

- `supabase/migrations/<timestamp>_prayer_scope.sql`
- `supabase/tests/remote_write_smoke.sql`

**Estimated scope:** Small (2 files)

## Checkpoint: Secure data contract

- [ ] Migration is additive and reversible through a forward corrective migration.
- [ ] Existing prayers remain Circle-only.
- [ ] Authorization matrix has explicit positive and negative coverage.

## Task 2: Read and write scoped prayers through the service layer

**Description:** Extend the TypeScript contracts and Supabase service mapping so both selected-Circle and organization contexts receive normalized prayer scope/destination data, and creation sends the approved destination without relying on client-only security.

**Acceptance criteria:**

- [ ] `PrayerRequest` and `PrayerInput` represent Circle and organization audiences without unsafe casts.
- [ ] With a selected Circle, reads return that Circle's prayers plus organization prayers; without one, reads return organization prayers only.
- [ ] Creation and prayer actions send consistent organization, person, scope, and optional Circle identifiers.

**Verification:**

- [ ] Focused service tests pass: `npm test -- src/services/circles.test.ts`
- [ ] TypeScript and production build pass: `npm run build`

**Dependencies:** Task 1

**Files likely touched:**

- `src/types.ts`
- `src/services/circles.ts`
- `src/services/circles.test.ts`

**Estimated scope:** Medium (3 files)

## Task 3: Support scoped creation in application state and demo mode

**Description:** Update application state mutations and demo fixtures so live and demo creation use the same safe defaults, destination labels, success messages, and no-selected-Circle behavior.

**Acceptance criteria:**

- [ ] Circle creation targets the selected Circle, while organization creation works without a selected Circle.
- [ ] Optimistic/demo prayer objects retain scope and destination data and produce destination-specific confirmation text.
- [ ] Existing prayer actions and rollback behavior continue to work for both audiences.

**Verification:**

- [ ] Focused context tests pass: `npm test -- src/AppContext.prayer.test.tsx`
- [ ] Existing authentication-context tests pass: `npm test -- src/AppContext.auth.test.tsx`
- [ ] Production build succeeds: `npm run build`

**Dependencies:** Task 2

**Files likely touched:**

- `src/AppContext.tsx`
- `src/data/demo.ts`
- `src/AppContext.prayer.test.tsx`

**Estimated scope:** Medium (3 files)

## Checkpoint: Integrated prayer state

- [ ] Focused service and context tests pass.
- [ ] Existing prayer creation and interaction behavior has no regressions.
- [ ] `npm run build` passes.

## Task 4: Add the audience selector, labels, and action permissions

**Description:** Present an accessible audience control in the prayer composer, show the resolved audience on every card, and render answer actions according to the author/Circle-leader/organization-admin matrix.

**Acceptance criteria:**

- [ ] The form defaults to the selected Circle, requires an explicit choice for organization sharing, and falls back to organization scope when no Circle is selected.
- [ ] Prayer cards clearly label the selected Circle or **Entire organization**, including answered prayers.
- [ ] The UI exposes mark-answered only to eligible users while the database remains the final enforcement boundary.

**Verification:**

- [ ] Prayer component tests pass: `npm test -- src/components/PrayerForm.test.tsx`
- [ ] Application prayer-page tests pass: `npm test -- src/App.test.tsx`
- [ ] Manual keyboard check confirms semantic labels, focus visibility, and audience selection.

**Dependencies:** Task 3

**Files likely touched:**

- `src/components/PrayerForm.tsx`
- `src/components/PrayerForm.test.tsx`
- `src/pages/PrayerPage.tsx`
- `src/App.test.tsx`

**Estimated scope:** Medium (4 files)

## Task 5: Verify and deploy the completed feature

**Description:** Run the complete quality gate, verify deployment targets, apply the database migration, deploy the Cloudflare application, and smoke-test the production behavior without exposing private content.

**Acceptance criteria:**

- [ ] All automated tests, the production build, and migration validation pass before deployment.
- [ ] The Supabase migration is applied before the Cloudflare application is deployed.
- [ ] Production smoke checks confirm both audiences, Circle switching, prayer actions, answer permissions, and anonymous denial.

**Verification:**

- [ ] Full tests pass: `npm test`
- [ ] Production build passes: `npm run build`
- [ ] Migration preview succeeds: `npx supabase db push --dry-run`
- [ ] Database deploy succeeds: `npx supabase db push`
- [ ] Application deploy succeeds: `npm run deploy`
- [ ] Authenticated and anonymous production smoke checks pass.

**Dependencies:** Task 4

**Files likely touched:**

- `tasks/todo.md`
- Deployment output only; no additional source file is expected.

**Estimated scope:** Small (1 tracking file plus deployment operations)

## Checkpoint: Complete

- [ ] Every success criterion in `SPEC-prayer-scope.md` is satisfied.
- [ ] No unrelated user changes were overwritten.
- [ ] Production runs the new database and application versions.
- [ ] Deployment URLs and smoke-check results are recorded in the implementation handoff.
