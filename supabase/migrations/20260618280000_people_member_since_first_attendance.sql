-- Track when a person first attended and when they became a member.
ALTER TABLE public.people
  ADD COLUMN IF NOT EXISTS first_attendance DATE,
  ADD COLUMN IF NOT EXISTS member_since DATE;
-- Backfill first visit date from existing join_date where not set.
UPDATE public.people
SET first_attendance = join_date
WHERE first_attendance IS NULL;
-- Backfill member_since for existing members.
UPDATE public.people
SET member_since = join_date
WHERE member_since IS NULL
  AND membership_type IN ('Member', 'Volunteer Worker', 'Worker');
