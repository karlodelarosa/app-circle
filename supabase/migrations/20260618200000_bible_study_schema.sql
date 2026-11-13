-- Household-based Bible study groups and participants (including guests from other households)

CREATE TABLE public.bible_study_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE RESTRICT,
  leader_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE RESTRICT,
  meeting_day TEXT NOT NULL DEFAULT '',
  meeting_time TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active' CHECK (
    status IN ('active', 'completed', 'paused', 'cancelled')
  ),
  start_date DATE NOT NULL DEFAULT CURRENT_DATE,
  completed_at TIMESTAMPTZ,
  status_notes TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX bible_study_groups_one_active_per_household_idx
  ON public.bible_study_groups (household_id)
  WHERE status = 'active';
CREATE TABLE public.bible_study_group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bible_study_group_id UUID NOT NULL REFERENCES public.bible_study_groups(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'Member' CHECK (role IN ('Leader', 'Member', 'Guest')),
  joined_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (bible_study_group_id, person_id)
);
CREATE INDEX bible_study_groups_organization_id_idx ON public.bible_study_groups(organization_id);
CREATE INDEX bible_study_groups_household_id_idx ON public.bible_study_groups(household_id);
CREATE INDEX bible_study_group_members_group_id_idx ON public.bible_study_group_members(bible_study_group_id);
CREATE INDEX bible_study_group_members_person_id_idx ON public.bible_study_group_members(person_id);
ALTER TABLE public.bible_study_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bible_study_group_members ENABLE ROW LEVEL SECURITY;
-- bible_study_groups policies
CREATE POLICY "Org members can view bible study groups"
  ON public.bible_study_groups FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = bible_study_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert bible study groups"
  ON public.bible_study_groups FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = bible_study_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update bible study groups"
  ON public.bible_study_groups FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = bible_study_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = bible_study_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete bible study groups"
  ON public.bible_study_groups FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = bible_study_groups.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- bible_study_group_members policies
CREATE POLICY "Org members can view bible study group members"
  ON public.bible_study_group_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.bible_study_groups bsg
      JOIN public.organization_members om ON om.organization_id = bsg.organization_id
      WHERE bsg.id = bible_study_group_members.bible_study_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert bible study group members"
  ON public.bible_study_group_members FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.bible_study_groups bsg
      JOIN public.organization_members om ON om.organization_id = bsg.organization_id
      WHERE bsg.id = bible_study_group_members.bible_study_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete bible study group members"
  ON public.bible_study_group_members FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.bible_study_groups bsg
      JOIN public.organization_members om ON om.organization_id = bsg.organization_id
      WHERE bsg.id = bible_study_group_members.bible_study_group_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
