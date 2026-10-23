# Implementation Plan: Prayer Audience Scope

## Overview

Implement the approved `prayer-scope` module from `SPEC-prayer-scope.md`. Members will choose between their selected Circle and their entire organization when creating a prayer. The database will enforce the chosen audience for reads, prayer responses, and answered-state changes. Existing prayers will remain Circle-scoped. After automated and targeted production checks pass, deploy the Supabase migration first and the Cloudflare application second.

## Architecture Decisions

- Add an explicit `scope` value (`circle` or `organization`) to prayer requests. Retain `cell_group_id` for Circle prayers and use a null Circle id for organization prayers, guarded by a database constraint.
- Default and backfill existing rows to `circle`; no existing prayer changes audience.
- Treat PostgreSQL policies/functions as the authorization boundary. React filtering improves presentation but is not security enforcement.
- Reuse the current organization membership, `circle_current_person_id`, `circle_can_access_group`, and `circle_can_lead_group` helpers rather than introducing a second membership model.
- Return the prayer scope and destination from both selected-Circle and organization-dashboard read paths. A selected Circle sees its own prayers plus organization prayers; no selected Circle sees organization prayers only.
- Keep prayer creation in the existing application context/service flow so demo and live modes retain matching behavior.
- Deploy in dependency order: database migration, application worker/assets, then authenticated smoke checks.

## Dependency Graph

```text
Database scope, constraints, authorization, and read contract
    |
    +-- Type and service mapping
            |
            +-- Application state and demo behavior
                    |
                    +-- Prayer form and prayer-card UI
                            |
                            +-- Full verification and deployment
```

## Task List

Detailed acceptance criteria and verification commands are tracked in `tasks/todo.md`.

### Phase 1: Secure data contract

- [ ] Task 1: Add the prayer audience database contract

### Checkpoint: Data contract

- [ ] Migration is additive, existing rows stay Circle-scoped, and authorization cases are covered by SQL tests

### Phase 2: Application feature slices

- [ ] Task 2: Read and write scoped prayers through the service layer
- [ ] Task 3: Support scoped creation in application state and demo mode

### Checkpoint: Integrated state

- [ ] Focused tests pass and the TypeScript production build succeeds

### Phase 3: Member experience

- [ ] Task 4: Add the audience selector, labels, and action permissions
- [ ] Task 5: Verify and deploy the completed feature

### Checkpoint: Complete

- [ ] All specification success criteria pass
- [ ] Supabase migration and Cloudflare application are deployed
- [ ] Production smoke checks confirm private, correctly scoped behavior

## Verification Checkpoints

1. After Task 1, validate the migration and review every read/write authorization path before application code depends on it.
2. After Tasks 2–3, run focused tests plus `npm run build` to verify service and state contracts.
3. After Task 4, run the entire suite and manually exercise both audiences in demo mode.
4. Task 5 is a release gate: do not deploy if tests, build, migration validation, or authorization checks fail.

## Parallelization

Tasks 1–4 are sequential because each consumes the preceding contract. Test cases may be written alongside each task, but shared types and application state should not be edited concurrently. Deployment is strictly sequential: Supabase before Cloudflare.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| A nullable Circle id accidentally broadens an existing prayer | High | Backfill explicit `circle` scope before relaxing nullability; add a scope/Circle consistency constraint and migration assertions. |
| Client filtering leaks Circle prayers through direct API access | High | Rebuild and test database read/write policies or secured functions for every prayer and prayer-click operation. |
| Organization prayers are duplicated or omitted when a Circle is selected | Medium | Define one normalized read contract and test selected-Circle and no-Circle contexts. |
| A Circle leader can answer an organization prayer | High | Encode the answer matrix in database authorization and test leader, author, admin, unrelated member, anonymous, and cross-organization cases. |
| The application deploys before its required schema | High | Apply and verify the Supabase migration before running the Cloudflare deploy command. |
| Production credentials or project linking are unavailable | Medium | Perform read-only CLI/link checks before deployment and stop without partial application deployment if the database target cannot be verified. |

## Deployment Sequence

```bash
npm test
npm run build
npx supabase db push --dry-run
npx supabase db push
npm run deploy
```

Before applying either deployment, verify the linked Supabase project and active Cloudflare account target. After deployment, perform authenticated smoke checks for Circle and organization creation, audience labels, visibility after Circle switching, **I prayed**, answered permissions, and anonymous/public denial.

## Open Questions

None.
