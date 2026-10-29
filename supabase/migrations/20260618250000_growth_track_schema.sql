-- Growth track activity log: follow-ups, contacts, visitations, stage changes

CREATE TYPE public.growth_track_activity_type AS ENUM (
  'follow_up_message',
  'follow_up_call',
  'contact',
  'visitation',
  'stage_advance',
  'group_placement',
  'outreach'
);
CREATE TABLE public.growth_track_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  activity_type public.growth_track_activity_type NOT NULL,
  notes TEXT,
  from_stage public.person_evangelism_stage,
  to_stage public.person_evangelism_stage,
  cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE SET NULL,
  life_group_id UUID REFERENCES public.life_groups(id) ON DELETE SET NULL,
  performed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  performed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX growth_track_activities_organization_id_idx
  ON public.growth_track_activities(organization_id);
CREATE INDEX growth_track_activities_person_id_idx
  ON public.growth_track_activities(person_id);
CREATE INDEX growth_track_activities_performed_at_idx
  ON public.growth_track_activities(performed_at DESC);
ALTER TABLE public.growth_track_activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members can view growth track activities"
  ON public.growth_track_activities FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = growth_track_activities.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert growth track activities"
  ON public.growth_track_activities FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = growth_track_activities.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update growth track activities"
  ON public.growth_track_activities FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = growth_track_activities.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = growth_track_activities.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete growth track activities"
  ON public.growth_track_activities FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = growth_track_activities.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
