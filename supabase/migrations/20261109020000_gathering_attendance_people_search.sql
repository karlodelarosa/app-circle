-- Let gathering managers search active People in the gathering's organization
-- without exposing the wider directory through a client-selected organization ID.

CREATE OR REPLACE FUNCTION public.search_circle_attendance_people(
  p_gathering_id UUID,
  p_query TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  gathering public.circle_gatherings%ROWTYPE;
  search_value TEXT := trim(coalesce(p_query, ''));
BEGIN
  SELECT * INTO gathering
  FROM public.circle_gatherings
  WHERE id = p_gathering_id;

  IF gathering.id IS NULL OR NOT public.circle_can_manage_gathering(gathering.id) THEN
    RAISE EXCEPTION 'Gathering manager access required';
  END IF;

  IF char_length(search_value) < 2 OR char_length(search_value) > 100 THEN
    RAISE EXCEPTION 'Search must be between 2 and 100 characters';
  END IF;

  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', person.id,
      'fullName', concat_ws(' ', person.first_name, person.last_name),
      'email', person.email
    ) ORDER BY person.last_name, person.first_name, person.id)
    FROM (
      SELECT candidate.*
      FROM public.people candidate
      WHERE candidate.organization_id = gathering.organization_id
        AND lower(candidate.status) = 'active'
        AND position(
          lower(search_value) IN lower(concat_ws(' ', candidate.first_name, candidate.last_name, candidate.email))
        ) > 0
      ORDER BY candidate.last_name, candidate.first_name, candidate.id
      LIMIT 30
    ) person
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.search_circle_attendance_people(UUID, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_circle_attendance_people(UUID, TEXT)
  TO authenticated;
