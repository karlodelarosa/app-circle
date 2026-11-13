-- Open Cell Group attendance, default meeting locations, and social contacts.

ALTER TABLE public.people
  ADD COLUMN IF NOT EXISTS social_contact TEXT NOT NULL DEFAULT '';
ALTER TABLE public.cell_groups
  ADD COLUMN IF NOT EXISTS location TEXT NOT NULL DEFAULT '';
CREATE TABLE IF NOT EXISTS public.cell_group_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID NOT NULL REFERENCES public.cell_groups(id) ON DELETE CASCADE,
  session_date DATE NOT NULL,
  leader_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  leader_name TEXT NOT NULL,
  location TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (cell_group_id, session_date)
);
CREATE TABLE IF NOT EXISTS public.cell_group_session_attendees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.cell_group_sessions(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, person_id)
);
CREATE INDEX IF NOT EXISTS cell_group_sessions_organization_date_idx
  ON public.cell_group_sessions(organization_id, session_date DESC);
CREATE INDEX IF NOT EXISTS cell_group_sessions_group_idx
  ON public.cell_group_sessions(cell_group_id);
CREATE INDEX IF NOT EXISTS cell_group_session_attendees_session_idx
  ON public.cell_group_session_attendees(session_id);
CREATE INDEX IF NOT EXISTS cell_group_session_attendees_person_idx
  ON public.cell_group_session_attendees(person_id);
ALTER TABLE public.cell_group_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cell_group_session_attendees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Org members can view cell group sessions" ON public.cell_group_sessions;
CREATE POLICY "Org members can view cell group sessions"
  ON public.cell_group_sessions FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.organization_id = cell_group_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org members can insert cell group sessions" ON public.cell_group_sessions;
CREATE POLICY "Org members can insert cell group sessions"
  ON public.cell_group_sessions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.organization_id = cell_group_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org members can update cell group sessions" ON public.cell_group_sessions;
CREATE POLICY "Org members can update cell group sessions"
  ON public.cell_group_sessions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.organization_id = cell_group_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.organization_id = cell_group_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org admins can delete cell group sessions" ON public.cell_group_sessions;
CREATE POLICY "Org admins can delete cell group sessions"
  ON public.cell_group_sessions FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.organization_id = cell_group_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org members can view cell group session attendees" ON public.cell_group_session_attendees;
CREATE POLICY "Org members can view cell group session attendees"
  ON public.cell_group_session_attendees FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.cell_group_sessions cgs
      JOIN public.organization_members om
        ON om.organization_id = cgs.organization_id
      WHERE cgs.id = cell_group_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org members can insert cell group session attendees" ON public.cell_group_session_attendees;
CREATE POLICY "Org members can insert cell group session attendees"
  ON public.cell_group_session_attendees FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.cell_group_sessions cgs
      JOIN public.organization_members om
        ON om.organization_id = cgs.organization_id
      WHERE cgs.id = cell_group_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org members can delete cell group session attendees" ON public.cell_group_session_attendees;
CREATE POLICY "Org members can delete cell group session attendees"
  ON public.cell_group_session_attendees FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.cell_group_sessions cgs
      JOIN public.organization_members om
        ON om.organization_id = cgs.organization_id
      WHERE cgs.id = cell_group_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE OR REPLACE FUNCTION public.record_cell_group_attendance(
  p_organization_id UUID,
  p_cell_group_id UUID,
  p_session_date DATE,
  p_leader_person_id UUID,
  p_leader_name TEXT,
  p_location TEXT,
  p_person_ids UUID[]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_session_id UUID;
  v_unique_person_count INT;
  v_org_person_count INT;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.organization_members om
    WHERE om.organization_id = p_organization_id
      AND om.user_id = auth.uid()
      AND om.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Not authorized for this organization';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.cell_groups
    WHERE id = p_cell_group_id AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'Cell Group does not belong to this organization';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.people
    WHERE id = p_leader_person_id AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'Meeting leader does not belong to this organization';
  END IF;

  SELECT COUNT(DISTINCT person_id)::int
  INTO v_unique_person_count
  FROM unnest(COALESCE(p_person_ids, ARRAY[]::UUID[])) AS attendee(person_id);

  SELECT COUNT(*)::int
  INTO v_org_person_count
  FROM public.people
  WHERE organization_id = p_organization_id
    AND id IN (
      SELECT DISTINCT person_id
      FROM unnest(COALESCE(p_person_ids, ARRAY[]::UUID[])) AS attendee(person_id)
    );

  IF v_org_person_count <> v_unique_person_count THEN
    RAISE EXCEPTION 'One or more attendees do not belong to this organization';
  END IF;

  SELECT id INTO v_session_id
  FROM public.cell_group_sessions
  WHERE cell_group_id = p_cell_group_id
    AND session_date = p_session_date;

  IF v_session_id IS NULL THEN
    INSERT INTO public.cell_group_sessions (
      organization_id,
      cell_group_id,
      session_date,
      leader_person_id,
      leader_name,
      location
    ) VALUES (
      p_organization_id,
      p_cell_group_id,
      p_session_date,
      p_leader_person_id,
      trim(p_leader_name),
      trim(p_location)
    )
    RETURNING id INTO v_session_id;
  ELSE
    UPDATE public.cell_group_sessions
    SET leader_person_id = p_leader_person_id,
        leader_name = trim(p_leader_name),
        location = trim(p_location),
        updated_at = now()
    WHERE id = v_session_id;
  END IF;

  DELETE FROM public.cell_group_session_attendees
  WHERE session_id = v_session_id;

  INSERT INTO public.cell_group_session_attendees (session_id, person_id)
  SELECT v_session_id, person_id
  FROM (
    SELECT DISTINCT person_id
    FROM unnest(COALESCE(p_person_ids, ARRAY[]::UUID[])) AS attendee(person_id)
  ) attendees;

  RETURN v_session_id;
END;
$$;
REVOKE ALL ON FUNCTION public.record_cell_group_attendance(
  UUID, UUID, DATE, UUID, TEXT, TEXT, UUID[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_cell_group_attendance(
  UUID, UUID, DATE, UUID, TEXT, TEXT, UUID[]
) TO authenticated;
DROP TRIGGER IF EXISTS enforce_cell_group_attendance_session_limit
  ON public.cell_group_sessions;
CREATE TRIGGER enforce_cell_group_attendance_session_limit
  BEFORE INSERT ON public.cell_group_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_attendance_session_limit();
CREATE OR REPLACE FUNCTION public.get_org_attendance_session_count(p_org_id UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (
    (
      SELECT COUNT(*)::int
      FROM public.service_sessions ss
      JOIN public.service_types st ON st.id = ss.service_type_id
      WHERE ss.organization_id = p_org_id
        AND st.category = 'sunday'
    )
    +
    (
      SELECT COUNT(*)::int
      FROM public.life_group_sessions
      WHERE organization_id = p_org_id
    )
    +
    (
      SELECT COUNT(*)::int
      FROM public.cell_group_sessions
      WHERE organization_id = p_org_id
    )
  );
$$;
