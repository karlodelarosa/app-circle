-- Discipleship groups: lightweight small groups with membership and a meeting/topic log

CREATE TABLE public.discipleship_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.discipleship_group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.discipleship_groups(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'Member' CHECK (role IN ('Leader', 'Member')),
  joined_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (group_id, person_id)
);
CREATE TABLE public.discipleship_group_meetings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.discipleship_groups(id) ON DELETE CASCADE,
  meeting_date DATE NOT NULL DEFAULT CURRENT_DATE,
  topic TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX discipleship_groups_organization_id_idx ON public.discipleship_groups(organization_id);
CREATE INDEX discipleship_group_members_group_id_idx ON public.discipleship_group_members(group_id);
CREATE INDEX discipleship_group_members_person_id_idx ON public.discipleship_group_members(person_id);
CREATE INDEX discipleship_group_meetings_group_id_idx ON public.discipleship_group_meetings(group_id);
ALTER TABLE public.discipleship_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discipleship_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discipleship_group_meetings ENABLE ROW LEVEL SECURITY;
-- discipleship_groups policies
CREATE POLICY "Org members can view discipleship groups"
  ON public.discipleship_groups FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = discipleship_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert discipleship groups"
  ON public.discipleship_groups FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = discipleship_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update discipleship groups"
  ON public.discipleship_groups FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = discipleship_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = discipleship_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete discipleship groups"
  ON public.discipleship_groups FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = discipleship_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- discipleship_group_members policies
CREATE POLICY "Org members can view discipleship group members"
  ON public.discipleship_group_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_members.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert discipleship group members"
  ON public.discipleship_group_members FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_members.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete discipleship group members"
  ON public.discipleship_group_members FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_members.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
-- discipleship_group_meetings policies
CREATE POLICY "Org members can view discipleship group meetings"
  ON public.discipleship_group_meetings FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_meetings.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert discipleship group meetings"
  ON public.discipleship_group_meetings FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_meetings.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete discipleship group meetings"
  ON public.discipleship_group_meetings FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_groups dg
      JOIN public.organization_members om ON om.organization_id = dg.organization_id
      WHERE dg.id = discipleship_group_meetings.group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
