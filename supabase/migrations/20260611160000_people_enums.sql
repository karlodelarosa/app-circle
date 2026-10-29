CREATE TYPE public.person_membership_type AS ENUM (
  'Worker',
  'Member',
  'Attender',
  'For Evangelism',
  'Prospect'
);
CREATE TYPE public.person_evangelism_stage AS ENUM (
  'First-time Attendee',
  'Follow-up',
  'Small Group',
  'Discipleship',
  'Worker'
);
UPDATE public.people
SET evangelism_stage = 'First-time Attendee'
WHERE evangelism_stage IS NULL OR trim(evangelism_stage) = '';
UPDATE public.people
SET membership_type = 'Attender'
WHERE membership_type IS NULL
   OR trim(membership_type) = ''
   OR membership_type NOT IN (
     'Worker', 'Member', 'Attender', 'For Evangelism', 'Prospect'
   );
ALTER TABLE public.people
  ALTER COLUMN membership_type DROP DEFAULT;
ALTER TABLE public.people
  ALTER COLUMN membership_type TYPE public.person_membership_type
  USING membership_type::public.person_membership_type;
ALTER TABLE public.people
  ALTER COLUMN membership_type SET DEFAULT 'Attender';
ALTER TABLE public.people
  ALTER COLUMN evangelism_stage DROP DEFAULT;
ALTER TABLE public.people
  ALTER COLUMN evangelism_stage TYPE public.person_evangelism_stage
  USING evangelism_stage::public.person_evangelism_stage;
ALTER TABLE public.people
  ALTER COLUMN evangelism_stage SET DEFAULT 'First-time Attendee';
ALTER TABLE public.people DROP COLUMN IF EXISTS name;
