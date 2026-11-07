BEGIN;

-- The gathering is already stored at 03:30 UTC, which is 11:30 in Manila.
-- Supply the organization's missing timezone so public pages do not fall back
-- to UTC when formatting gathering dates and times.
INSERT INTO public.circle_organization_settings (
  organization_id,
  timezone
)
VALUES (
  'de0be306-6302-4c0c-9253-1c6df0a8ad71',
  'Asia/Manila'
)
ON CONFLICT (organization_id) DO UPDATE
SET
  timezone = EXCLUDED.timezone,
  updated_at = now();

COMMIT;
