ALTER TYPE public.person_membership_type ADD VALUE IF NOT EXISTS 'Volunteer Worker';
ALTER TABLE public.people
  ALTER COLUMN birthdate DROP NOT NULL;
