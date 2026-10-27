# Circles

Circles is a simple app for cell groups, small-group gatherings, and the people who make them meaningful.

It gives leaders and members one place to keep up with their circle, plan gatherings, welcome guests, and stay connected throughout the week.

## What you can do

- Create and manage cell-group gatherings
- Share gathering details through a public page
- Let guests RSVP or check in when they arrive
- Keep track of members, visitors, and new connections
- Record attendance and follow up with people
- Share announcements, photos, testimonies, and group updates
- Collect and respond to prayer requests
- Help people find a circle and express interest in joining

## Made for community

Circles is designed to support the life of a cell group beyond the meeting itself. It helps leaders prepare well, makes it easier for guests to take part, and gives everyone a clear way to stay informed and connected.

The app works alongside SheepCount, using the same member accounts and church information while giving cell groups their own focused space.

## Running the app

```bash
npm install
npm run dev
```

The signed-in area requires a SheepCount account or a Member ID created by a Circle leader. Public community pages and gathering invitations remain available without signing in.

## Deploying to Cloudflare

Build the Cloudflare version:

```bash
npm run build:cf
```

Preview it locally with Wrangler:

```bash
npm run preview
```

Deploy it to Cloudflare Workers:

```bash
npm run deploy
```

The first deployment may ask you to sign in to Cloudflare. The Supabase URL and publishable key are included when the app is built, so make sure they are available in `.env.local` before deploying.

### Cloudflare dashboard setup

In **Workers & Pages**, create or connect a Worker to the `karlodelarosa/app-circle` GitHub repository. Use these settings:

| Setting | Value |
| --- | --- |
| Worker name | `app-circle` |
| Production branch | `main` |
| Root directory | `/` (repository root) |
| Build command | `npm run build:cf` |
| Deploy command | `npx wrangler deploy` |
| Version command | `npx wrangler versions upload` |

Add these as build variables before deploying:

| Variable | Value |
| --- | --- |
| `VITE_SUPABASE_URL` | The Supabase project URL used by SheepCount |
| `VITE_SUPABASE_PUBLISHABLE_OR_ANON_KEY` | The Supabase publishable or anon key used by SheepCount |

These are build-time values. Add them under the Worker's build settings.

The Worker also generates gathering preview metadata for Messenger and other
social apps. Deploy this version once so Cloudflare recognizes the Worker entry
point, then add these under **Settings → Variables and Secrets → Runtime** and
redeploy:

| Variable | Value |
| --- | --- |
| `SUPABASE_URL` | The same Supabase project URL used above |
| `SUPABASE_ANON_KEY` | The same public publishable or anon key used above |

Use only the public publishable/anon key here, never the Supabase service-role
key. Circles now has a Worker entry point in addition to its static assets, so
Cloudflare accepts runtime variables for this deployment.

### Existing invitation links

Older invitations use a Supabase Edge Function URL. Deploy the included
compatibility redirect after linking the Supabase CLI to the SheepCount
project:

```bash
npx supabase functions deploy circle-gathering-share --project-ref qrmpogczieanpahxxxkc
```

Set the Edge Function secret `CIRCLES_PUBLIC_ORIGIN` to
`https://circles.elgchurch.com`. New invitations use the normal public RSVP URL
directly; the Edge Function only keeps previously shared links working.

### Circle member accounts

Circle leaders can give app access to an active person who is already part of
their Circle. Existing SheepCount accounts are linked automatically. People
without an account receive a Member ID and a one-time temporary password. New
Member IDs use a short first-name-and-digits format such as `john-4827`.
Previously issued Member IDs remain valid and are not renamed.

Account access is managed from **My Circles → open a Circle → Our people →
Manage access**. Organization administrators can record a Discipleship badge
and then separately approve that person for leadership. Promotion changes a
generated Member ID into normal SheepCount email credentials; it does not move
the person out of their current Circle. New Circles can only be created by an
organization administrator and must be assigned to an approved leader.

Apply the current database migrations, then deploy the two authenticated Edge
Functions used for account creation and password changes:

```bash
npx supabase db push
npx supabase functions deploy circle-member-access --project-ref qrmpogczieanpahxxxkc
npx supabase functions deploy circle-change-password --project-ref qrmpogczieanpahxxxkc
```

The functions use Supabase’s built-in project secrets. Do not add or expose a
service-role key in Cloudflare or in browser environment variables.

### Circle content assignments

Gatherings, galleries, testimonies, and Circle announcements always show their
destination before publishing. After applying the latest migration, existing
content is intentionally marked **Needs review** and is hidden from private
Circle detail pages until an organization administrator confirms or corrects
it under **Publish → Content assignments**. Public organization pages remain
available during this review. Reassignment keeps existing links and media;
gatherings with RSVP or attendance records cannot be moved.

After saving the settings, Cloudflare will build and deploy every new commit pushed to `main`. Other branches can use the version command to create a version without replacing the production deployment.
