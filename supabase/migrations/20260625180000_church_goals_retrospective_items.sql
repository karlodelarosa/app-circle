-- Retrospective items (many per category) replacing single text fields on yearly goals

CREATE TABLE public.church_yearly_goal_retrospective_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  yearly_goal_id UUID NOT NULL REFERENCES public.church_yearly_goals(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (
    category IN ('went_well', 'could_be_better', 'action_point')
  ),
  text TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX church_yearly_goal_retrospective_items_goal_id_idx
  ON public.church_yearly_goal_retrospective_items(yearly_goal_id);
CREATE INDEX church_yearly_goal_retrospective_items_category_idx
  ON public.church_yearly_goal_retrospective_items(yearly_goal_id, category);
-- Migrate existing text fields into individual items (split by line)
INSERT INTO public.church_yearly_goal_retrospective_items (yearly_goal_id, category, text, sort_order)
SELECT
  g.id,
  v.category,
  trim(line),
  (row_number() OVER (PARTITION BY g.id, v.category ORDER BY ord))::INT - 1
FROM public.church_yearly_goals g
CROSS JOIN LATERAL (
  VALUES
    ('went_well'::TEXT, g.went_well),
    ('could_be_better'::TEXT, g.could_be_better),
    ('action_point'::TEXT, g.action_points)
) AS v(category, body)
CROSS JOIN LATERAL unnest(string_to_array(v.body, E'\n')) WITH ORDINALITY AS t(line, ord)
WHERE trim(line) <> '';
ALTER TABLE public.church_yearly_goals
  DROP COLUMN went_well,
  DROP COLUMN could_be_better,
  DROP COLUMN action_points;
ALTER TABLE public.church_yearly_goal_retrospective_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members with church_goals module can view retrospective items"
  ON public.church_yearly_goal_retrospective_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      JOIN public.organization_members om ON om.organization_id = yg.organization_id
      WHERE yg.id = church_yearly_goal_retrospective_items.yearly_goal_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      WHERE yg.id = church_yearly_goal_retrospective_items.yearly_goal_id
        AND public.org_has_module(yg.organization_id, 'church_goals')
    )
  );
CREATE POLICY "Org admins with church_goals module can insert retrospective items"
  ON public.church_yearly_goal_retrospective_items FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      JOIN public.organization_members om ON om.organization_id = yg.organization_id
      WHERE yg.id = church_yearly_goal_retrospective_items.yearly_goal_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      WHERE yg.id = church_yearly_goal_retrospective_items.yearly_goal_id
        AND public.org_has_module(yg.organization_id, 'church_goals')
    )
  );
CREATE POLICY "Org admins with church_goals module can update retrospective items"
  ON public.church_yearly_goal_retrospective_items FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      JOIN public.organization_members om ON om.organization_id = yg.organization_id
      WHERE yg.id = church_yearly_goal_retrospective_items.yearly_goal_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      WHERE yg.id = church_yearly_goal_retrospective_items.yearly_goal_id
        AND public.org_has_module(yg.organization_id, 'church_goals')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      JOIN public.organization_members om ON om.organization_id = yg.organization_id
      WHERE yg.id = church_yearly_goal_retrospective_items.yearly_goal_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      WHERE yg.id = church_yearly_goal_retrospective_items.yearly_goal_id
        AND public.org_has_module(yg.organization_id, 'church_goals')
    )
  );
CREATE POLICY "Org admins with church_goals module can delete retrospective items"
  ON public.church_yearly_goal_retrospective_items FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      JOIN public.organization_members om ON om.organization_id = yg.organization_id
      WHERE yg.id = church_yearly_goal_retrospective_items.yearly_goal_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_yearly_goals yg
      WHERE yg.id = church_yearly_goal_retrospective_items.yearly_goal_id
        AND public.org_has_module(yg.organization_id, 'church_goals')
    )
  );
