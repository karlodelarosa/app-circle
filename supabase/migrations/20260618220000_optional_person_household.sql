-- People do not require a household; assign one later when known.
ALTER TABLE public.people
  ALTER COLUMN household_id DROP NOT NULL;
