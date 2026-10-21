# Circles

Circles is the public and member-facing community companion to SheepCount. It is a standalone Vite/React PWA that shares SheepCount's Supabase project, authentication, organizations, People, cell groups, and official attendance records.

## Run locally

```bash
npm install
npm run dev
```

Without environment variables the app uses a complete local demo. The authenticated experience starts at `/`.

To connect SheepCount:

1. Copy `.env.example` to `.env.local` and use the same Supabase URL and publishable/anon key as SheepCount.
2. Confirm SheepCount's existing `20261017010000_circles_integration.sql` migration is present in the shared database.
3. Apply `supabase/migrations/20261017130000_circles_public_mvp.sql` once from this repository. Future `circle_*` migrations belong here and must not be duplicated in SheepCount's migration stream.
4. Add the Circles deployment URL to Supabase Auth's allowed redirects.
5. Publish an organization public space from the authenticated Content page.

Existing SheepCount email/password credentials are used. Circles does not register users or infer links between auth users and People. Person-specific participation requires an existing active `circle_user_links` record.

## Ownership

- SheepCount owns organizations, auth memberships, People, cell groups, leaders, subscriptions, and official attendance.
- Circles owns `circle_*` gatherings, RSVPs, public pages, testimonies, galleries, announcements, and interest submissions.
- Anonymous RSVP and interest forms use restricted RPCs and never create People records.

## Checks

```bash
npm test
npm run build
```
