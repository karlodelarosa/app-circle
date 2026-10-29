-- Add schedule field to life groups and dedicated attendance tracking

ALTER TABLE public.life_groups
  ADD COLUMN IF NOT EXISTS schedule TEXT NOT NULL DEFAULT '';
CREATE TABLE IF NOT EXISTS public.life_group_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  life_group_id UUID NOT NULL REFERENCES public.life_groups(id) ON DELETE CASCADE,
  session_date DATE NOT NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (life_group_id, session_date)
);
CREATE TABLE IF NOT EXISTS public.life_group_session_attendees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.life_group_sessions(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, person_id)
);
CREATE INDEX IF NOT EXISTS life_group_sessions_life_group_id_idx
  ON public.life_group_sessions(life_group_id);
CREATE INDEX IF NOT EXISTS life_group_sessions_organization_id_idx
  ON public.life_group_sessions(organization_id);
CREATE INDEX IF NOT EXISTS life_group_sessions_session_date_idx
  ON public.life_group_sessions(organization_id, session_date DESC);
CREATE INDEX IF NOT EXISTS life_group_session_attendees_session_id_idx
  ON public.life_group_session_attendees(session_id);
CREATE INDEX IF NOT EXISTS life_group_session_attendees_person_id_idx
  ON public.life_group_session_attendees(person_id);
ALTER TABLE public.life_group_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.life_group_session_attendees ENABLE ROW LEVEL SECURITY;
-- life_group_sessions policies
DROP POLICY IF EXISTS "Org members can view life group sessions" ON public.life_group_sessions;
CREATE POLICY "Org members can view life group sessions"
  ON public.life_group_sessions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = life_group_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org members can insert life group sessions" ON public.life_group_sessions;
CREATE POLICY "Org members can insert life group sessions"
  ON public.life_group_sessions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = life_group_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org members can update life group sessions" ON public.life_group_sessions;
CREATE POLICY "Org members can update life group sessions"
  ON public.life_group_sessions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = life_group_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = life_group_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org admins can delete life group sessions" ON public.life_group_sessions;
CREATE POLICY "Org admins can delete life group sessions"
  ON public.life_group_sessions FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = life_group_sessions.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- life_group_session_attendees policies
DROP POLICY IF EXISTS "Org members can view life group session attendees" ON public.life_group_session_attendees;
CREATE POLICY "Org members can view life group session attendees"
  ON public.life_group_session_attendees FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.life_group_sessions lgs
      JOIN public.organization_members om ON om.organization_id = lgs.organization_id
      WHERE lgs.id = life_group_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org members can insert life group session attendees" ON public.life_group_session_attendees;
CREATE POLICY "Org members can insert life group session attendees"
  ON public.life_group_session_attendees FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.life_group_sessions lgs
      JOIN public.organization_members om ON om.organization_id = lgs.organization_id
      WHERE lgs.id = life_group_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org members can delete life group session attendees" ON public.life_group_session_attendees;
CREATE POLICY "Org members can delete life group session attendees"
  ON public.life_group_session_attendees FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.life_group_sessions lgs
      JOIN public.organization_members om ON om.organization_id = lgs.organization_id
      WHERE lgs.id = life_group_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
