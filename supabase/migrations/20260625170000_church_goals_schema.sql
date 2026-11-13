-- Church yearly goals, objectives, and monthly themes

CREATE TABLE public.church_yearly_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  year INT NOT NULL,
  theme TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  vision TEXT NOT NULL DEFAULT '',
  went_well TEXT NOT NULL DEFAULT '',
  could_be_better TEXT NOT NULL DEFAULT '',
  action_points TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, year)
);
CREATE TABLE public.church_yearly_goal_objectives (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  yearly_goal_id UUID NOT NULL REFERENCES public.church_yearly_goals(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_completed BOOLEAN NOT NULL DEFAULT false,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.church_monthly_themes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  year INT NOT NULL,
  month INT NOT NULL CHECK (month BETWEEN 1 AND 12),
  title TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, year, month)
);
CREATE INDEX church_yearly_goals_organization_id_idx
  ON public.church_yearly_goals(organization_id);
CREATE INDEX church_yearly_goals_year_idx
  ON public.church_yearly_goals(year DESC);
CREATE INDEX church_yearly_goal_objectives_yearly_goal_id_idx
  ON public.church_yearly_goal_objectives(yearly_goal_id);
CREATE INDEX church_monthly_themes_organization_id_idx
  ON public.church_monthly_themes(organization_id);
CREATE INDEX church_monthly_themes_year_month_idx
  ON public.church_monthly_themes(year DESC, month);
ALTER TABLE public.church_yearly_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.church_yearly_goal_objectives ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.church_monthly_themes ENABLE ROW LEVEL SECURITY;
-- church_yearly_goals policies
CREATE POLICY "Org members with church_goals module can view yearly goals"
  ON public.church_yearly_goals FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_yearly_goals.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(church_yearly_goals.organization_id, 'church_goals')
  );
CREATE POLICY "Org admins with church_goals module can insert yearly goals"
  ON public.church_yearly_goals FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_yearly_goals.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_yearly_goals.organization_id, 'church_goals')
  );
CREATE POLICY "Org admins with church_goals module can update yearly goals"
  ON public.church_yearly_goals FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_yearly_goals.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_yearly_goals.organization_id, 'church_goals')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_yearly_goals.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_yearly_goals.organization_id, 'church_goals')
  );
CREATE POLICY "Org admins with church_goals module can delete yearly goals"
  ON public.church_yearly_goals FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_yearly_goals.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_yearly_goals.organization_id, 'church_goals')
  );
-- church_yearly_goal_objectives policies
CREATE POLICY "Org members with church_goals module can view objectives"
  ON public.church_yearly_goal_objectives FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      JOIN public.organization_members om ON om.organization_id = yg.organization_id
      WHERE yg.id = church_yearly_goal_objectives.yearly_goal_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      WHERE yg.id = church_yearly_goal_objectives.yearly_goal_id
        AND public.org_has_module(yg.organization_id, 'church_goals')
    )
  );
CREATE POLICY "Org admins with church_goals module can insert objectives"
  ON public.church_yearly_goal_objectives FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      JOIN public.organization_members om ON om.organization_id = yg.organization_id
      WHERE yg.id = church_yearly_goal_objectives.yearly_goal_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      WHERE yg.id = church_yearly_goal_objectives.yearly_goal_id
        AND public.org_has_module(yg.organization_id, 'church_goals')
    )
  );
CREATE POLICY "Org admins with church_goals module can update objectives"
  ON public.church_yearly_goal_objectives FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      JOIN public.organization_members om ON om.organization_id = yg.organization_id
      WHERE yg.id = church_yearly_goal_objectives.yearly_goal_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      WHERE yg.id = church_yearly_goal_objectives.yearly_goal_id
        AND public.org_has_module(yg.organization_id, 'church_goals')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      JOIN public.organization_members om ON om.organization_id = yg.organization_id
      WHERE yg.id = church_yearly_goal_objectives.yearly_goal_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      WHERE yg.id = church_yearly_goal_objectives.yearly_goal_id
        AND public.org_has_module(yg.organization_id, 'church_goals')
    )
  );
CREATE POLICY "Org admins with church_goals module can delete objectives"
  ON public.church_yearly_goal_objectives FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      JOIN public.organization_members om ON om.organization_id = yg.organization_id
      WHERE yg.id = church_yearly_goal_objectives.yearly_goal_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      WHERE yg.id = church_yearly_goal_objectives.yearly_goal_id
        AND public.org_has_module(yg.organization_id, 'church_goals')
    )
  );
-- church_monthly_themes policies
CREATE POLICY "Org members with church_goals module can view monthly themes"
  ON public.church_monthly_themes FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_monthly_themes.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(church_monthly_themes.organization_id, 'church_goals')
  );
CREATE POLICY "Org admins with church_goals module can insert monthly themes"
  ON public.church_monthly_themes FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_monthly_themes.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_monthly_themes.organization_id, 'church_goals')
  );
CREATE POLICY "Org admins with church_goals module can update monthly themes"
  ON public.church_monthly_themes FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_monthly_themes.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_monthly_themes.organization_id, 'church_goals')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_monthly_themes.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_monthly_themes.organization_id, 'church_goals')
  );
CREATE POLICY "Org admins with church_goals module can delete monthly themes"
  ON public.church_monthly_themes FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_monthly_themes.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_monthly_themes.organization_id, 'church_goals')
  );
