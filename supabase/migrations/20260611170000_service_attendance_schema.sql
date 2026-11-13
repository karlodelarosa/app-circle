CREATE TYPE public.service_category AS ENUM ('sunday', 'life_group');
CREATE TABLE public.service_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  category public.service_category NOT NULL DEFAULT 'life_group',
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name)
);
CREATE TABLE public.service_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  service_type_id UUID NOT NULL REFERENCES public.service_types(id) ON DELETE CASCADE,
  session_date DATE NOT NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, service_type_id, session_date)
);
CREATE TABLE public.service_session_attendees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.service_sessions(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, person_id)
);
CREATE INDEX service_types_organization_id_idx ON public.service_types(organization_id);
CREATE INDEX service_sessions_organization_id_idx ON public.service_sessions(organization_id);
CREATE INDEX service_sessions_session_date_idx ON public.service_sessions(organization_id, session_date DESC);
CREATE INDEX service_session_attendees_session_id_idx ON public.service_session_attendees(session_id);
CREATE INDEX service_session_attendees_person_id_idx ON public.service_session_attendees(person_id);
ALTER TABLE public.service_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_session_attendees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members can view service types"
  ON public.service_types FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = service_types.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert service types"
  ON public.service_types FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = service_types.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can view service sessions"
  ON public.service_sessions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = service_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert service sessions"
  ON public.service_sessions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = service_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update service sessions"
  ON public.service_sessions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = service_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = service_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete service sessions"
  ON public.service_sessions FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = service_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can view session attendees"
  ON public.service_session_attendees FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.service_sessions ss
      JOIN public.organization_members om ON om.organization_id = ss.organization_id
      WHERE ss.id = service_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert session attendees"
  ON public.service_session_attendees FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.service_sessions ss
      JOIN public.organization_members om ON om.organization_id = ss.organization_id
      WHERE ss.id = service_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete session attendees"
  ON public.service_session_attendees FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.service_sessions ss
      JOIN public.organization_members om ON om.organization_id = ss.organization_id
      WHERE ss.id = service_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE OR REPLACE FUNCTION public.seed_default_service_types(org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.service_types WHERE organization_id = org_id) THEN
    INSERT INTO public.service_types (organization_id, name, category, sort_order)
    VALUES
      (org_id, 'Sunday Service', 'sunday', 1),
      (org_id, 'Sunday School', 'life_group', 2),
      (org_id, 'Men''s Fellowship', 'life_group', 3),
      (org_id, 'Ladies'' Fellowship', 'life_group', 4),
      (org_id, 'Young Professionals Fellowship', 'life_group', 5),
      (org_id, 'Prayer Meeting', 'life_group', 6);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.seed_default_service_types(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seed_default_service_types(UUID) TO authenticated;
