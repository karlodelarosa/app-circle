-- Life groups (demographic fellowships), work ministries (service teams), and cell groups (small accountability groups)

CREATE TABLE public.life_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL CHECK (category IN ('Children', 'Youth', 'Adults')),
  color TEXT NOT NULL DEFAULT 'purple',
  sort_order INT NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name)
);
CREATE TABLE public.life_group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  life_group_id UUID NOT NULL REFERENCES public.life_groups(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  joined_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (life_group_id, person_id)
);
CREATE TABLE public.work_ministries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  color TEXT NOT NULL DEFAULT 'purple',
  sort_order INT NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name)
);
CREATE TABLE public.work_ministry_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_ministry_id UUID NOT NULL REFERENCES public.work_ministries(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'Member',
  assigned_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (work_ministry_id, person_id)
);
CREATE TABLE public.cell_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  leader_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'graduated', 'multiplied')),
  parent_cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.cell_group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cell_group_id UUID NOT NULL REFERENCES public.cell_groups(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'Member' CHECK (role IN ('Leader', 'Member')),
  joined_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (cell_group_id, person_id)
);
CREATE INDEX life_groups_organization_id_idx ON public.life_groups(organization_id);
CREATE INDEX life_group_members_life_group_id_idx ON public.life_group_members(life_group_id);
CREATE INDEX life_group_members_person_id_idx ON public.life_group_members(person_id);
CREATE INDEX work_ministries_organization_id_idx ON public.work_ministries(organization_id);
CREATE INDEX work_ministry_members_work_ministry_id_idx ON public.work_ministry_members(work_ministry_id);
CREATE INDEX work_ministry_members_person_id_idx ON public.work_ministry_members(person_id);
CREATE INDEX cell_groups_organization_id_idx ON public.cell_groups(organization_id);
CREATE INDEX cell_group_members_cell_group_id_idx ON public.cell_group_members(cell_group_id);
CREATE INDEX cell_group_members_person_id_idx ON public.cell_group_members(person_id);
ALTER TABLE public.life_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.life_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_ministries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_ministry_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cell_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cell_group_members ENABLE ROW LEVEL SECURITY;
-- life_groups policies
CREATE POLICY "Org members can view life groups"
  ON public.life_groups FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = life_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert life groups"
  ON public.life_groups FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = life_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update life groups"
  ON public.life_groups FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = life_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = life_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete life groups"
  ON public.life_groups FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = life_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- life_group_members policies
CREATE POLICY "Org members can view life group members"
  ON public.life_group_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.life_groups lg
      JOIN public.organization_members om ON om.organization_id = lg.organization_id
      WHERE lg.id = life_group_members.life_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert life group members"
  ON public.life_group_members FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.life_groups lg
      JOIN public.organization_members om ON om.organization_id = lg.organization_id
      WHERE lg.id = life_group_members.life_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete life group members"
  ON public.life_group_members FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.life_groups lg
      JOIN public.organization_members om ON om.organization_id = lg.organization_id
      WHERE lg.id = life_group_members.life_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
-- work_ministries policies
CREATE POLICY "Org members can view work ministries"
  ON public.work_ministries FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = work_ministries.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert work ministries"
  ON public.work_ministries FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = work_ministries.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update work ministries"
  ON public.work_ministries FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = work_ministries.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = work_ministries.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete work ministries"
  ON public.work_ministries FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = work_ministries.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- work_ministry_members policies
CREATE POLICY "Org members can view work ministry members"
  ON public.work_ministry_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.work_ministries wm
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wm.id = work_ministry_members.work_ministry_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert work ministry members"
  ON public.work_ministry_members FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.work_ministries wm
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wm.id = work_ministry_members.work_ministry_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update work ministry members"
  ON public.work_ministry_members FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.work_ministries wm
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wm.id = work_ministry_members.work_ministry_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.work_ministries wm
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wm.id = work_ministry_members.work_ministry_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete work ministry members"
  ON public.work_ministry_members FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.work_ministries wm
      JOIN public.organization_members om ON om.organization_id = wm.organization_id
      WHERE wm.id = work_ministry_members.work_ministry_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
-- cell_groups policies
CREATE POLICY "Org members can view cell groups"
  ON public.cell_groups FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = cell_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert cell groups"
  ON public.cell_groups FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = cell_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update cell groups"
  ON public.cell_groups FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = cell_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = cell_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete cell groups"
  ON public.cell_groups FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = cell_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- cell_group_members policies
CREATE POLICY "Org members can view cell group members"
  ON public.cell_group_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.cell_groups cg
      JOIN public.organization_members om ON om.organization_id = cg.organization_id
      WHERE cg.id = cell_group_members.cell_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert cell group members"
  ON public.cell_group_members FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.cell_groups cg
      JOIN public.organization_members om ON om.organization_id = cg.organization_id
      WHERE cg.id = cell_group_members.cell_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete cell group members"
  ON public.cell_group_members FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.cell_groups cg
      JOIN public.organization_members om ON om.organization_id = cg.organization_id
      WHERE cg.id = cell_group_members.cell_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE OR REPLACE FUNCTION public.seed_default_life_groups(org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.life_groups WHERE organization_id = org_id) THEN
    INSERT INTO public.life_groups (organization_id, name, description, category, color, sort_order, is_default)
    VALUES
      (org_id, 'Children''s Fellowship', 'Fellowship and Bible lessons for children', 'Children', 'blue', 1, true),
      (org_id, 'Youth Fellowship', 'Fellowship for teens and young adults', 'Youth', 'green', 2, true),
      (org_id, 'Ladies'' Fellowship', 'Fellowship for women', 'Adults', 'pink', 3, true),
      (org_id, 'Men''s Fellowship', 'Fellowship for men', 'Adults', 'indigo', 4, true),
      (org_id, 'Young Professionals Fellowship', 'Fellowship for working professionals', 'Adults', 'purple', 5, true);
  END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.seed_default_work_ministries(org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.work_ministries WHERE organization_id = org_id) THEN
    INSERT INTO public.work_ministries (organization_id, name, description, color, sort_order, is_default)
    VALUES
      (org_id, 'Worship Ministry', 'Music, worship leading, and creative arts', 'purple', 1, true),
      (org_id, 'Hospitality & Ushering', 'Welcoming guests and ushering services', 'orange', 2, true),
      (org_id, 'Deacons', 'Church deacons and service support', 'blue', 3, true),
      (org_id, 'Mission/Outreach', 'Evangelism and community outreach', 'green', 4, true),
      (org_id, 'Christian Education', 'Teaching, Sunday school, and discipleship', 'red', 5, true);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.seed_default_life_groups(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.seed_default_work_ministries(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seed_default_life_groups(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seed_default_work_ministries(UUID) TO authenticated;
