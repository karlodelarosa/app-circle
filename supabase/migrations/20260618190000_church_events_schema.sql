-- Church events and registrations (VBS, Camp, Retreat, Conference)

CREATE TABLE public.church_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL CHECK (type IN ('VBS', 'Camp', 'Retreat', 'Conference')),
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (
    status IN ('draft', 'published', 'completed', 'cancelled')
  ),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (end_date >= start_date)
);
CREATE TABLE public.church_event_registrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.church_events(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  parent_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  role_in_event TEXT NOT NULL DEFAULT 'Attendee' CHECK (
    role_in_event IN ('Attendee', 'Volunteer', 'Core_Leader')
  ),
  attendance_status TEXT NOT NULL DEFAULT 'registered' CHECK (
    attendance_status IN ('registered', 'checked_in', 'attended', 'no_show', 'cancelled')
  ),
  medical_notes TEXT NOT NULL DEFAULT '',
  dietary_restrictions TEXT NOT NULL DEFAULT '',
  registered_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (event_id, person_id)
);
CREATE INDEX church_events_organization_id_idx ON public.church_events(organization_id);
CREATE INDEX church_events_start_date_idx ON public.church_events(start_date);
CREATE INDEX church_event_registrations_event_id_idx ON public.church_event_registrations(event_id);
CREATE INDEX church_event_registrations_person_id_idx ON public.church_event_registrations(person_id);
CREATE INDEX church_event_registrations_parent_person_id_idx ON public.church_event_registrations(parent_person_id);
ALTER TABLE public.church_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.church_event_registrations ENABLE ROW LEVEL SECURITY;
-- church_events policies
CREATE POLICY "Org members can view church events"
  ON public.church_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_events.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert church events"
  ON public.church_events FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_events.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update church events"
  ON public.church_events FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_events.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_events.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete church events"
  ON public.church_events FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_events.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- church_event_registrations policies
CREATE POLICY "Org members can view church event registrations"
  ON public.church_event_registrations FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_events ce
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ce.id = church_event_registrations.event_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert church event registrations"
  ON public.church_event_registrations FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_events ce
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ce.id = church_event_registrations.event_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update church event registrations"
  ON public.church_event_registrations FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_events ce
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ce.id = church_event_registrations.event_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_events ce
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ce.id = church_event_registrations.event_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete church event registrations"
  ON public.church_event_registrations FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_events ce
      JOIN public.organization_members om ON om.organization_id = ce.organization_id
      WHERE ce.id = church_event_registrations.event_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
