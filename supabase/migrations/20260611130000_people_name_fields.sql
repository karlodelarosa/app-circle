ALTER TABLE public.people
  ADD COLUMN IF NOT EXISTS first_name TEXT,
  ADD COLUMN IF NOT EXISTS middle_name TEXT,
  ADD COLUMN IF NOT EXISTS last_name TEXT;
UPDATE public.people
SET
  first_name = COALESCE(
    NULLIF(split_part(trim(name), ' ', 1), ''),
    trim(name)
  ),
  last_name = COALESCE(
    NULLIF(
      split_part(
        trim(name),
        ' ',
        GREATEST(array_length(string_to_array(trim(name), ' '), 1), 1)
      ),
      ''
    ),
    trim(name)
  )
WHERE first_name IS NULL OR last_name IS NULL;
ALTER TABLE public.people
  ALTER COLUMN first_name SET NOT NULL,
  ALTER COLUMN last_name SET NOT NULL;
CREATE INDEX IF NOT EXISTS people_organization_last_name_idx
  ON public.people(organization_id, last_name, first_name);
