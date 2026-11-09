BEGIN;

CREATE OR REPLACE FUNCTION public.resolve_circle_connection(
  p_connection_id UUID,
  p_person_id UUID DEFAULT NULL,
  p_first_name TEXT DEFAULT '',
  p_last_name TEXT DEFAULT '',
  p_email TEXT DEFAULT '',
  p_phone TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  connection public.circle_guest_connections%ROWTYPE;
  resolved_person_id UUID := p_person_id;
  created_new BOOLEAN := false;
BEGIN
  SELECT * INTO connection
  FROM public.circle_guest_connections
  WHERE id = p_connection_id
  FOR UPDATE;

  IF connection.id IS NULL OR connection.cell_group_id IS NULL THEN
    RAISE EXCEPTION 'Assign this guest to a Circle before connecting them to SheepCount';
  END IF;
  IF NOT (
    public.circle_is_org_admin(connection.organization_id)
    OR public.circle_can_lead_group(connection.cell_group_id)
  ) THEN
    RAISE EXCEPTION 'Leader access required';
  END IF;
  IF connection.converted_person_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'personId', connection.converted_person_id,
      'created', false,
      'alreadyConnected', true
    );
  END IF;
  IF resolved_person_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.people person
    WHERE person.id = resolved_person_id
      AND person.organization_id = connection.organization_id
  ) THEN
    RAISE EXCEPTION 'Person is outside this organization';
  END IF;

  IF resolved_person_id IS NULL THEN
    SELECT person.id INTO resolved_person_id
    FROM public.people person
    WHERE person.organization_id = connection.organization_id
      AND (
        (
          COALESCE(NULLIF(trim(p_email), ''), connection.email) <> ''
          AND lower(person.email) = lower(COALESCE(NULLIF(trim(p_email), ''), connection.email))
        )
        OR (
          COALESCE(NULLIF(trim(p_phone), ''), connection.phone) <> ''
          AND person.phone = COALESCE(NULLIF(trim(p_phone), ''), connection.phone)
        )
      )
    ORDER BY person.created_at
    LIMIT 1;
    IF resolved_person_id IS NOT NULL THEN
      RAISE EXCEPTION 'A matching SheepCount person already exists. Select that person instead';
    END IF;
    IF nullif(trim(p_first_name), '') IS NULL OR nullif(trim(p_last_name), '') IS NULL THEN
      RAISE EXCEPTION 'First and last name are required for a new visitor';
    END IF;
    INSERT INTO public.people(
      organization_id, household_id, first_name, last_name, email, phone,
      birthdate, role, status, membership_type, evangelism_stage,
      is_prospect, join_date
    )
    VALUES (
      connection.organization_id, NULL, trim(p_first_name), trim(p_last_name),
      lower(COALESCE(NULLIF(trim(p_email), ''), connection.email)),
      COALESCE(NULLIF(trim(p_phone), ''), connection.phone),
      NULL, 'Single', 'Active', 'Prospect', 'Small Group', true, current_date
    )
    RETURNING id INTO resolved_person_id;
    created_new := true;
  END IF;

  INSERT INTO public.cell_group_members(cell_group_id, person_id, role)
  VALUES (connection.cell_group_id, resolved_person_id, 'Member')
  ON CONFLICT (cell_group_id, person_id) DO NOTHING;
  UPDATE public.circle_guest_connections
  SET converted_person_id = resolved_person_id,
      status = 'connected',
      last_activity_at = now(),
      updated_at = now()
  WHERE id = connection.id;
  UPDATE public.circle_guest_rsvps
  SET converted_person_id = resolved_person_id, updated_at = now()
  WHERE connection_id = connection.id;
  UPDATE public.circle_join_interests
  SET status = 'closed', updated_at = now()
  WHERE connection_id = connection.id;
  INSERT INTO public.circle_guest_connection_activities(
    organization_id, connection_id, activity_type, body, created_by
  )
  VALUES (
    connection.organization_id,
    connection.id,
    'converted',
    CASE
      WHEN created_new THEN 'Registered as a SheepCount visitor.'
      ELSE 'Matched to an existing SheepCount person.'
    END,
    auth.uid()
  );
  RETURN jsonb_build_object(
    'personId', resolved_person_id,
    'created', created_new,
    'alreadyConnected', false
  );
END;
$$;

COMMIT;
