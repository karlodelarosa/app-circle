DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type type_row
    JOIN pg_namespace namespace_row ON namespace_row.oid = type_row.typnamespace
    WHERE namespace_row.nspname = 'public'
      AND type_row.typname = 'person_membership_type'
  ) THEN
    CREATE TYPE public.person_membership_type AS ENUM (
      'Worker',
      'Member',
      'Attender',
      'For Evangelism',
      'Prospect'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_type type_row
    JOIN pg_namespace namespace_row ON namespace_row.oid = type_row.typnamespace
    WHERE namespace_row.nspname = 'public'
      AND type_row.typname = 'person_evangelism_stage'
  ) THEN
    CREATE TYPE public.person_evangelism_stage AS ENUM (
      'First-time Attendee',
      'Follow-up',
      'Small Group',
      'Discipleship',
      'Worker'
    );
  END IF;
END;
$$;

DO $$
DECLARE
  membership_udt TEXT;
  evangelism_udt TEXT;
BEGIN
  SELECT udt_name INTO membership_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'people'
    AND column_name = 'membership_type';

  IF membership_udt IS DISTINCT FROM 'person_membership_type' THEN
    UPDATE public.people
    SET membership_type = 'Attender'
    WHERE membership_type IS NULL
       OR trim(membership_type::TEXT) = ''
       OR membership_type::TEXT NOT IN (
         'Worker', 'Member', 'Attender', 'For Evangelism', 'Prospect'
       );
    ALTER TABLE public.people ALTER COLUMN membership_type DROP DEFAULT;
    ALTER TABLE public.people
      ALTER COLUMN membership_type TYPE public.person_membership_type
      USING membership_type::TEXT::public.person_membership_type;
    ALTER TABLE public.people ALTER COLUMN membership_type SET DEFAULT 'Attender';
  END IF;

  SELECT udt_name INTO evangelism_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'people'
    AND column_name = 'evangelism_stage';

  IF evangelism_udt IS DISTINCT FROM 'person_evangelism_stage' THEN
    UPDATE public.people
    SET evangelism_stage = 'First-time Attendee'
    WHERE evangelism_stage IS NULL OR trim(evangelism_stage::TEXT) = '';
    ALTER TABLE public.people ALTER COLUMN evangelism_stage DROP DEFAULT;
    ALTER TABLE public.people
      ALTER COLUMN evangelism_stage TYPE public.person_evangelism_stage
      USING evangelism_stage::TEXT::public.person_evangelism_stage;
    ALTER TABLE public.people ALTER COLUMN evangelism_stage SET DEFAULT 'First-time Attendee';
  END IF;
END;
$$;

ALTER TABLE public.people DROP COLUMN IF EXISTS name;
