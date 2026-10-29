-- Sub-teams within work ministries (e.g. Production Team under Worship Ministry)
-- and predefined service roles per team (e.g. Musician, Audio Tech)

CREATE TABLE public.work_ministry_teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_ministry_id UUID NOT NULL REFERENCES public.work_ministries(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (work_ministry_id, name)
);
CREATE TABLE public.work_ministry_team_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_ministry_team_id UUID NOT NULL REFERENCES public.work_ministry_teams(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (work_ministry_team_id, name)
);
ALTER TABLE public.work_ministry_members
  ADD COLUMN team_id UUID REFERENCES public.work_ministry_teams(id) ON DELETE SET NULL,
  ADD COLUMN service_role TEXT NOT NULL DEFAULT '';
CREATE INDEX work_ministry_teams_ministry_id_idx ON public.work_ministry_teams(work_ministry_id);
CREATE INDEX work_ministry_team_roles_team_id_idx ON public.work_ministry_team_roles(work_ministry_team_id);
CREATE INDEX work_ministry_members_team_id_idx ON public.work_ministry_members(team_id);
ALTER TABLE public.work_ministry_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_ministry_team_roles ENABLE ROW LEVEL SECURITY;
-- work_ministry_teams policies
CREATE POLICY "Org members can view work ministry teams"
  ON public.work_ministry_teams FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.work_ministries wm
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wm.id = work_ministry_teams.work_ministry_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert work ministry teams"
  ON public.work_ministry_teams FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.work_ministries wm
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wm.id = work_ministry_teams.work_ministry_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update work ministry teams"
  ON public.work_ministry_teams FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.work_ministries wm
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wm.id = work_ministry_teams.work_ministry_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.work_ministries wm
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wm.id = work_ministry_teams.work_ministry_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete work ministry teams"
  ON public.work_ministry_teams FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.work_ministries wm
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wm.id = work_ministry_teams.work_ministry_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
-- work_ministry_team_roles policies
CREATE POLICY "Org members can view work ministry team roles"
  ON public.work_ministry_team_roles FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.work_ministry_teams wmt
      JOIN public.work_ministries wm ON wm.id = wmt.work_ministry_id
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wmt.id = work_ministry_team_roles.work_ministry_team_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert work ministry team roles"
  ON public.work_ministry_team_roles FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.work_ministry_teams wmt
      JOIN public.work_ministries wm ON wm.id = wmt.work_ministry_id
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wmt.id = work_ministry_team_roles.work_ministry_team_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update work ministry team roles"
  ON public.work_ministry_team_roles FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.work_ministry_teams wmt
      JOIN public.work_ministries wm ON wm.id = wmt.work_ministry_id
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wmt.id = work_ministry_team_roles.work_ministry_team_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.work_ministry_teams wmt
      JOIN public.work_ministries wm ON wm.id = wmt.work_ministry_id
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wmt.id = work_ministry_team_roles.work_ministry_team_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete work ministry team roles"
  ON public.work_ministry_team_roles FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.work_ministry_teams wmt
      JOIN public.work_ministries wm ON wm.id = wmt.work_ministry_id
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wmt.id = work_ministry_team_roles.work_ministry_team_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
