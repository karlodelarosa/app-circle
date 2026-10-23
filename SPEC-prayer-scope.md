# Spec: Prayer Audience Scope

Module id: `prayer-scope`

## Objective

Allow an authenticated Circles member to choose whether a new prayer request is shared with their currently selected Circle or with every active member of their organization.

The feature must preserve the private nature of the prayer wall while making the selected audience clear at creation time and wherever a prayer is displayed.

### User stories

- As an authenticated member, I can share a prayer with only my currently selected Circle.
- As an authenticated member, I can share a prayer with my entire organization.
- As a prayer-wall participant, I can tell whether a prayer belongs to a Circle or the whole organization.
- As an eligible viewer, I can pray for a request and see its praise report.
- As the prayer's author or an authorized leader, I can mark it answered.

### Audience and authorization rules

| Prayer scope | Creation target | Who can view and pray | Who can mark answered |
| --- | --- | --- | --- |
| Circle | The member's currently selected Circle | Active members of that Circle, its leader, and organization administrators | The author, that Circle's leader, and organization administrators |
| Organization | The member's current organization | Active members of the organization | The author and organization administrators |

- Prayer requests remain authenticated, private application content. They must never be returned by public-space or public-gathering APIs.
- “I prayed,” prayer counts, answered status, and praise reports use the same audience authorization as the parent prayer.
- A Circle-scoped prayer must have a Circle id belonging to the same organization.
- An organization-scoped prayer must not be assigned to a Circle.
- Existing prayer requests are treated as Circle-scoped and retain their existing Circle assignment.
- The initial audience selection is **My Circle** to preserve current behavior and reduce accidental broad sharing.
- A member must explicitly choose **Entire organization** before submitting an organization-wide prayer.
- A member without a currently selected Circle may create an organization-wide prayer, but cannot create a Circle-scoped prayer until a Circle is selected.

## Tech Stack

- React 18.3 with TypeScript 5.6
- React Router 7
- Supabase JavaScript client 2.57
- PostgreSQL/Supabase migrations and row-level security
- Tailwind CSS 3.4 plus the existing shared component classes
- Vitest 2.1 and Testing Library 16

## Commands

```bash
# Install dependencies
npm install

# Start the Vite development server
npm run dev

# Run the automated test suite once
npm test

# Type-check and produce the production build
npm run build

# Build the Cloudflare deployment target
npm run build:cf
```

The project does not currently define a separate lint command. No lint command will be invented as part of this module.

## Project Structure

```text
src/types.ts                    Shared prayer scope and request contracts
src/components/PrayerForm.tsx   Prayer creation form and audience selector
src/pages/PrayerPage.tsx        Prayer wall, audience labels, and actions
src/AppContext.tsx              Prayer creation and optimistic application state
src/services/circles.ts         Supabase reads and prayer mutations
src/data/demo.ts                Demo-mode prayer fixtures and behavior
src/**/*.test.ts(x)             Vitest unit and component tests
supabase/migrations/            Additive schema, query, and RLS changes
supabase/tests/                 Database authorization and write smoke tests
```

## Code Style

Use TypeScript unions for closed domain values, camelCase for variables and functions, PascalCase for React components and interfaces, and snake_case only at the database boundary. Keep authorization rules explicit rather than inferring them from display text.

```ts
export type PrayerScope = "circle" | "organization";

export interface PrayerInput {
  title: string;
  description: string;
  category: PrayerCategory;
  scope: PrayerScope;
}

const destinationLabel =
  prayer.scope === "organization"
    ? "Entire organization"
    : prayer.destinationName;
```

Follow the repository's existing two-space indentation and component/service separation. User-facing controls must use semantic labels and retain visible keyboard focus behavior.

## Functional Requirements

### Creating a prayer

- The prayer form presents an audience choice between **My Circle** and **Entire organization**.
- **My Circle** shows the selected Circle's name so the destination is unambiguous.
- The form defaults to **My Circle** when a Circle is selected.
- If no Circle is selected, **My Circle** is unavailable and the form defaults to **Entire organization**.
- Submission stores the chosen scope and its valid destination.
- Success feedback names the destination: the selected Circle or the organization.
- Existing title, description, category, and length validation remains unchanged.

### Reading and interacting

- The prayer wall includes organization-wide prayers plus prayers for the currently selected Circle.
- A prayer card displays its audience using the Circle name or **Entire organization**.
- Organization-wide prayers remain visible when the member changes between Circles in the same organization.
- Members outside a Circle cannot read that Circle's prayers through direct database or API access.
- Any eligible viewer may add or remove their own **I prayed** response.
- Prayer counts include only valid responses to the parent request.

### Answering prayers

- The prayer author may mark their own request answered.
- A Circle leader may mark a request answered only when it belongs to their Circle.
- An organization administrator may mark any prayer in their organization answered.
- A Circle leader who is not the author cannot mark an organization-wide prayer answered.
- Answered prayers and praise reports retain the original audience.

### Migration and compatibility

- The database change is additive and preserves all existing prayer ids, timestamps, authors, responses, and answered state.
- Every existing request is backfilled or interpreted as `circle` scope.
- Existing Circle ids remain intact.
- Demo mode follows the same audience behavior as the Supabase-backed application.

## Testing Strategy

Use Vitest and Testing Library for application behavior and SQL smoke/policy tests for authorization boundaries.

### Component and application tests

- The form defaults to the selected Circle and clearly displays its name.
- A member can explicitly select the organization audience.
- With no selected Circle, Circle scope is unavailable and organization scope is selected.
- Submitted input contains the selected scope.
- Prayer cards render the correct audience label.
- The mark-answered control follows the author, Circle-leader, and organization-admin matrix.
- Demo-mode creation matches persisted-mode behavior.

### Service and database tests

- Circle and organization prayer rows are written with consistent scope/destination values.
- Existing prayer rows remain Circle-scoped after migration.
- Active organization members can read and pray for organization-wide requests.
- Members cannot read or interact with prayers from inaccessible Circles.
- Circle leaders cannot answer organization-wide prayers they did not author.
- Organization administrators can answer either scope.
- Public and anonymous roles cannot read prayer requests or prayer responses.
- Cross-organization ids are rejected for reads and mutations.

All existing tests must remain green. Verification requires both `npm test` and `npm run build`.

## Boundaries

### Always do

- Enforce audience rules in PostgreSQL/RLS or secured database functions, not only in React.
- Validate that the prayer, person, Circle, and organization belong to the same organization.
- Use an additive, forward-only Supabase migration.
- Preserve existing private-prayer behavior during migration.
- Provide accessible labels and keyboard-operable audience controls.
- Run the automated tests and production build before considering the module complete.

### Ask first

- Changing the approved audience or mark-answered authorization matrix.
- Allowing prayer authors to select a Circle other than the current Circle.
- Adding moderation, deletion, editing, anonymous posting, or notifications.
- Adding a dependency or changing deployment/CI configuration.
- Exposing any prayer content through public pages or unauthenticated APIs.

### Never do

- Put authorization solely in client-side filtering.
- Make existing Circle prayers organization-wide during migration.
- Expose prayer content, author details, or response activity publicly.
- Commit credentials, service-role keys, or production member data.
- weaken or remove tests to make the feature pass.

## Success Criteria

- An authenticated member can create a prayer for their selected Circle or their entire organization.
- The form defaults safely and makes the destination explicit before submission.
- Eligible members see the correct combined prayer wall for their context.
- Every prayer card identifies its audience.
- View, **I prayed**, prayer-count, answer, and praise-report behavior follows the authorization table.
- Existing prayers remain Circle-only with no data loss.
- Anonymous users, other organizations, and members of unrelated Circles cannot access restricted prayer data.
- Demo mode and Supabase-backed mode present equivalent behavior.
- `npm test` and `npm run build` pass.

## Open Questions

None. The permission rule for organization-wide prayers is specified conservatively as author or organization administrator only and can be revised during review.
