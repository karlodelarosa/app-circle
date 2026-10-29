-- Per-session attendance for church events (VBS, Camp, Retreat, Conference)

CREATE TABLE public.church_event_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.church_events(id) ON DELETE CASCADE,
  session_date DATE NOT NULL,
  session_label TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (event_id, session_date, session_label)
);
CREATE TABLE public.church_event_session_attendees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.church_event_sessions(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, person_id)
);
CREATE INDEX church_event_sessions_event_id_idx ON public.church_event_sessions(event_id);
CREATE INDEX church_event_sessions_session_date_idx ON public.church_event_sessions(session_date);
CREATE INDEX church_event_session_attendees_session_id_idx ON public.church_event_session_attendees(session_id);
CREATE INDEX church_event_session_attendees_person_id_idx ON public.church_event_session_attendees(person_id);
ALTER TABLE public.church_event_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.church_event_session_attendees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members can view church event sessions"
  ON public.church_event_sessions FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_events ce
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ce.id = church_event_sessions.event_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert church event sessions"
  ON public.church_event_sessions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_events ce
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ce.id = church_event_sessions.event_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update church event sessions"
  ON public.church_event_sessions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_events ce
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ce.id = church_event_sessions.event_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_events ce
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ce.id = church_event_sessions.event_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete church event sessions"
  ON public.church_event_sessions FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_events ce
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ce.id = church_event_sessions.event_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can view church event session attendees"
  ON public.church_event_session_attendees FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_event_sessions ces
      JOIN public.church_events ce ON ce.id = ces.event_id
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ces.id = church_event_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert church event session attendees"
  ON public.church_event_session_attendees FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_event_sessions ces
      JOIN public.church_events ce ON ce.id = ces.event_id
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ces.id = church_event_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete church event session attendees"
  ON public.church_event_session_attendees FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_event_sessions ces
      JOIN public.church_events ce ON ce.id = ces.event_id
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ces.id = church_event_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
