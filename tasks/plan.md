# Implementation Plan: Short Member IDs and Role-Aware Prayer Destinations

## Overview

Use short `first-name-####` IDs for newly generated member accounts while preserving every existing login. Extend the prayer audience feature so regular members post privately to their active Circle, while leaders and administrators can choose any accessible Circle. Organization-wide sharing remains available to everyone.

## Architecture Decisions

- Keep existing Member IDs immutable; only new provisioning and replacement-login creation use the short format.
- Check both `circle_user_links.login_id` and Supabase Auth email availability before issuing an ID.
- Add an optional `groupId` to `PrayerInput`; require it for Circle scope and discard it for organization scope.
- Use `data.groups` as the leader/admin destination list and retain PostgreSQL/RLS as the authorization boundary.
- Load a different chosen Circle only after prayer creation succeeds, so failures never switch application context.
- No database migration is required.

## Delivery Order

1. Add and test the reusable Member ID generator, then wire it into the member-access Edge Function.
2. Add and test the prayer destination contract, role-aware UI, and cross-Circle success behavior.
3. Update sign-in guidance and the existing prayer specification.
4. Run the full test/build/database checks, then deploy the Edge Function and frontend from an isolated clean worktree.

## Verification

- Focused tests cover ID normalization/collisions and prayer role/destination behavior.
- `npm test` and `npm run build` pass.
- Supabase migration dry-run reports no unexpected database change.
- Browser verification confirms accessible labels, keyboard behavior, responsive layout, and a clean console.
- Production smoke checks confirm short-ID sign-in and private/organization prayer destinations.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| New ID collides with an Auth account not represented in `circle_user_links` | Check both stores and retry with a new four-digit suffix. |
| A failed prayer post changes the active Circle | Create first; load the destination Circle only after success. |
| Client manipulation targets an inaccessible Circle | Validate against loaded Circles and retain existing RLS enforcement. |
| Deployment includes unrelated local gathering work | Build and deploy the frontend from an isolated clean worktree containing only this feature. |
