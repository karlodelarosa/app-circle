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

The app includes demo content, so it can be explored locally without connecting a live church account. From the demo account menu, members can sign in using the same email and password they use for SheepCount.

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

These are build-time values. Add them under the Worker's build settings rather than as runtime-only Worker variables.

After saving the settings, Cloudflare will build and deploy every new commit pushed to `main`. Other branches can use the version command to create a version without replacing the production deployment.
