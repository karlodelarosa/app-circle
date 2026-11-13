-- Training courses, modules, person progress, and Cell Leader gate

CREATE TABLE public.training_courses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL CHECK (
    category IN ('Ministry', 'Life Skills', 'Leadership', 'Safety', 'Administration', 'Worship')
  ),
  slug TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name),
  UNIQUE (organization_id, slug)
);
CREATE TABLE public.training_course_modules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID NOT NULL REFERENCES public.training_courses(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.person_course_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID NOT NULL REFERENCES public.training_courses(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed')),
  completed_module_ids UUID[] NOT NULL DEFAULT '{}',
  monday_mission_action TEXT NOT NULL DEFAULT '',
  enrolled_date DATE NOT NULL DEFAULT CURRENT_DATE,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (course_id, person_id)
);
CREATE INDEX training_courses_organization_id_idx ON public.training_courses(organization_id);
CREATE INDEX training_course_modules_course_id_idx ON public.training_course_modules(course_id);
CREATE INDEX person_course_progress_course_id_idx ON public.person_course_progress(course_id);
CREATE INDEX person_course_progress_person_id_idx ON public.person_course_progress(person_id);
ALTER TABLE public.training_courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.training_course_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.person_course_progress ENABLE ROW LEVEL SECURITY;
-- training_courses policies
CREATE POLICY "Org members can view training courses"
  ON public.training_courses FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = training_courses.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert training courses"
  ON public.training_courses FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = training_courses.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update training courses"
  ON public.training_courses FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = training_courses.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = training_courses.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete training courses"
  ON public.training_courses FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = training_courses.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- training_course_modules policies
CREATE POLICY "Org members can view training course modules"
  ON public.training_course_modules FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.training_courses tc
      JOIN public.organization_members om ON om.organization_id = tc.organization_id
      WHERE tc.id = training_course_modules.course_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert training course modules"
  ON public.training_course_modules FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.training_courses tc
      JOIN public.organization_members om ON om.organization_id = tc.organization_id
      WHERE tc.id = training_course_modules.course_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update training course modules"
  ON public.training_course_modules FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.training_courses tc
      JOIN public.organization_members om ON om.organization_id = tc.organization_id
      WHERE tc.id = training_course_modules.course_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.training_courses tc
      JOIN public.organization_members om ON om.organization_id = tc.organization_id
      WHERE tc.id = training_course_modules.course_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete training course modules"
  ON public.training_course_modules FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.training_courses tc
      JOIN public.organization_members om ON om.organization_id = tc.organization_id
      WHERE tc.id = training_course_modules.course_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- person_course_progress policies
CREATE POLICY "Org members can view person course progress"
  ON public.person_course_progress FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.training_courses tc
      JOIN public.organization_members om ON om.organization_id = tc.organization_id
      WHERE tc.id = person_course_progress.course_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert person course progress"
  ON public.person_course_progress FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.training_courses tc
      JOIN public.organization_members om ON om.organization_id = tc.organization_id
      WHERE tc.id = person_course_progress.course_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update person course progress"
  ON public.person_course_progress FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.training_courses tc
      JOIN public.organization_members om ON om.organization_id = tc.organization_id
      WHERE tc.id = person_course_progress.course_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.training_courses tc
      JOIN public.organization_members om ON om.organization_id = tc.organization_id
      WHERE tc.id = person_course_progress.course_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete person course progress"
  ON public.person_course_progress FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.training_courses tc
      JOIN public.organization_members om ON om.organization_id = tc.organization_id
      WHERE tc.id = person_course_progress.course_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
-- Cell group members UPDATE policy (missing from groups_ministry_schema)
CREATE POLICY "Org members can update cell group members"
  ON public.cell_group_members FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.cell_groups cg
      JOIN public.organization_members om ON om.organization_id = cg.organization_id
      WHERE cg.id = cell_group_members.cell_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
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
-- Cell Leader training gate
CREATE OR REPLACE FUNCTION public.enforce_cell_leader_training()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  org_id UUID;
  course_completed BOOLEAN;
BEGIN
  IF NEW.role != 'Leader' THEN
    RETURN NEW;
  END IF;

  SELECT cg.organization_id INTO org_id
  FROM public.cell_groups cg
  WHERE cg.id = NEW.cell_group_id;

  SELECT EXISTS (
    SELECT 1
    FROM public.person_course_progress pcp
    JOIN public.training_courses tc ON tc.id = pcp.course_id
    WHERE pcp.person_id = NEW.person_id
      AND tc.organization_id = org_id
      AND tc.slug = 'cell-leadership-101'
      AND pcp.status = 'completed'
  ) INTO course_completed;

  IF NOT course_completed THEN
    RAISE EXCEPTION 'Cell Leadership 101 must be completed before assigning Cell Leader role';
  END IF;

  RETURN NEW;
END;
$$;
CREATE TRIGGER enforce_cell_leader_training_trigger
  BEFORE INSERT OR UPDATE OF role ON public.cell_group_members
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_cell_leader_training();
CREATE OR REPLACE FUNCTION public.seed_default_training_courses(org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  course_cell_leadership UUID;
  course_worship UUID;
  course_finances UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.training_courses WHERE organization_id = org_id) THEN
    INSERT INTO public.training_courses (
      organization_id, name, description, category, slug, sort_order, is_default
    ) VALUES (
      org_id,
      'Cell Leadership 101',
      'Foundational training for leading a cell group',
      'Leadership',
      'cell-leadership-101',
      1,
      true
    )
    RETURNING id INTO course_cell_leadership;

    INSERT INTO public.training_courses (
      organization_id, name, description, category, slug, sort_order, is_default
    ) VALUES (
      org_id,
      'Worship Leading Basics',
      'Core skills for worship leaders and musicians',
      'Worship',
      'worship-leading-basics',
      2,
      true
    )
    RETURNING id INTO course_worship;

    INSERT INTO public.training_courses (
      organization_id, name, description, category, slug, sort_order, is_default
    ) VALUES (
      org_id,
      'Church Finances 101',
      'Stewardship and financial management for ministry',
      'Administration',
      'church-finances-101',
      3,
      true
    )
    RETURNING id INTO course_finances;

    INSERT INTO public.training_course_modules (course_id, name, description, sort_order) VALUES
      (course_cell_leadership, 'Cell group vision and values', 'Understand the purpose and DNA of cell groups', 1),
      (course_cell_leadership, 'Facilitating meaningful discussion', 'Lead engaging Bible discussions in small groups', 2),
      (course_cell_leadership, 'Pastoral care basics', 'Care for members through life seasons', 3),
      (course_cell_leadership, 'Multiplication readiness', 'Prepare to multiply your cell group', 4);

    INSERT INTO public.training_course_modules (course_id, name, description, sort_order) VALUES
      (course_worship, 'Worship theology', 'Biblical foundations of worship leading', 1),
      (course_worship, 'Team coordination', 'Rehearse, plan sets, and lead a worship team', 2),
      (course_worship, 'Sunday service flow', 'Run a complete worship segment', 3);

    INSERT INTO public.training_course_modules (course_id, name, description, sort_order) VALUES
      (course_finances, 'Biblical stewardship', 'Principles of faithful financial management', 1),
      (course_finances, 'Budgeting for ministry', 'Plan and track ministry budgets', 2),
      (course_finances, 'Reporting and accountability', 'Transparent financial reporting practices', 3);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.seed_default_training_courses(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seed_default_training_courses(UUID) TO authenticated;
