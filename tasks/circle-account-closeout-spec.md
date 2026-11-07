# Circle account isolation and gathering closeout

## Account boundary

- Organization administrators retain their SheepCount subscription-owner login and may use both applications.
- Every non-admin Circle member or leader is authorized in Circles through `circle_user_links`; an active SheepCount `organization_members` row is neither required nor created.
- Provisioned Member IDs carry `app_metadata.account_scope = "circles"`.
- Approved leaders may create any number of Circles, but non-admin leaders can assign only themselves as primary leader.

## Gathering closeout

- Gathering managers save attendance, selected guest RSVPs, staged newcomers, and private notes through one transaction.
- First completion sets an immutable `finalized_at` and `editable_until = finalized_at + 7 days`.
- At or after `editable_until`, the server rejects all closeout changes. Completed gatherings are never reopened.
- Closeout notes are manager-only and separate from member reflections.

## Newcomers

- First name, last name, and birthdate are required.
- Exact active People matches are reused; ambiguous or inactive matches are rejected for manual resolution.
- A missing match creates an Active SheepCount Prospect at the Small Group evangelism stage.
- Attendance creation never creates a Circle membership or login.

## Release gate

The canonical remote-only SheepCount migration `20261105110000` must be reconciled locally before applying `20261107010000` to staging or production.
