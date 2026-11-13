-- Discipleship tracks, enrollments, milestones, and milestone completions

CREATE TABLE public.discipleship_tracks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL CHECK (category IN ('Foundation', 'Growth', 'Leadership', 'Mentorship')),
  duration TEXT NOT NULL DEFAULT '',
  schedule TEXT NOT NULL DEFAULT '',
  leader_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  color TEXT NOT NULL DEFAULT 'blue',
  sort_order INT NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name)
);
CREATE TABLE public.discipleship_enrollments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  track_id UUID NOT NULL REFERENCES public.discipleship_tracks(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  mentor_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  role TEXT NOT NULL DEFAULT 'Learner' CHECK (role IN ('Learner', 'Guide')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'paused')),
  enrolled_date DATE NOT NULL DEFAULT CURRENT_DATE,
  current_module TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (track_id, person_id)
);
CREATE TABLE public.discipleship_milestones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  track_id UUID NOT NULL REFERENCES public.discipleship_tracks(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.discipleship_milestone_completions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  enrollment_id UUID NOT NULL REFERENCES public.discipleship_enrollments(id) ON DELETE CASCADE,
  milestone_id UUID NOT NULL REFERENCES public.discipleship_milestones(id) ON DELETE CASCADE,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  notes TEXT NOT NULL DEFAULT '',
  completed_by_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (enrollment_id, milestone_id)
);
CREATE INDEX discipleship_tracks_organization_id_idx ON public.discipleship_tracks(organization_id);
CREATE INDEX discipleship_enrollments_track_id_idx ON public.discipleship_enrollments(track_id);
CREATE INDEX discipleship_enrollments_person_id_idx ON public.discipleship_enrollments(person_id);
CREATE INDEX discipleship_milestones_track_id_idx ON public.discipleship_milestones(track_id);
CREATE INDEX discipleship_milestone_completions_enrollment_id_idx ON public.discipleship_milestone_completions(enrollment_id);
ALTER TABLE public.discipleship_tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discipleship_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discipleship_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discipleship_milestone_completions ENABLE ROW LEVEL SECURITY;
-- discipleship_tracks policies
CREATE POLICY "Org members can view discipleship tracks"
  ON public.discipleship_tracks FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = discipleship_tracks.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert discipleship tracks"
  ON public.discipleship_tracks FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = discipleship_tracks.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update discipleship tracks"
  ON public.discipleship_tracks FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = discipleship_tracks.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = discipleship_tracks.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete discipleship tracks"
  ON public.discipleship_tracks FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = discipleship_tracks.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- discipleship_milestones policies
CREATE POLICY "Org members can view discipleship milestones"
  ON public.discipleship_milestones FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_milestones.track_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert discipleship milestones"
  ON public.discipleship_milestones FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_milestones.track_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update discipleship milestones"
  ON public.discipleship_milestones FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_milestones.track_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_milestones.track_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org admins can delete discipleship milestones"
  ON public.discipleship_milestones FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_milestones.track_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
-- discipleship_enrollments policies
CREATE POLICY "Org members can view discipleship enrollments"
  ON public.discipleship_enrollments FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_enrollments.track_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert discipleship enrollments"
  ON public.discipleship_enrollments FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_enrollments.track_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update discipleship enrollments"
  ON public.discipleship_enrollments FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_enrollments.track_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_enrollments.track_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete discipleship enrollments"
  ON public.discipleship_enrollments FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_tracks dt
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE dt.id = discipleship_enrollments.track_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
-- discipleship_milestone_completions policies
CREATE POLICY "Org members can view milestone completions"
  ON public.discipleship_milestone_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_enrollments de
      JOIN public.discipleship_tracks dt ON dt.id = de.track_id
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE de.id = discipleship_milestone_completions.enrollment_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert milestone completions"
  ON public.discipleship_milestone_completions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.discipleship_enrollments de
      JOIN public.discipleship_tracks dt ON dt.id = de.track_id
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE de.id = discipleship_milestone_completions.enrollment_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update milestone completions"
  ON public.discipleship_milestone_completions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_enrollments de
      JOIN public.discipleship_tracks dt ON dt.id = de.track_id
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE de.id = discipleship_milestone_completions.enrollment_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.discipleship_enrollments de
      JOIN public.discipleship_tracks dt ON dt.id = de.track_id
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE de.id = discipleship_milestone_completions.enrollment_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete milestone completions"
  ON public.discipleship_milestone_completions FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.discipleship_enrollments de
      JOIN public.discipleship_tracks dt ON dt.id = de.track_id
      JOIN public.organization_members om ON om.organization_id = dt.organization_id
      WHERE de.id = discipleship_milestone_completions.enrollment_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE OR REPLACE FUNCTION public.seed_default_discipleship_tracks(org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  track_new_believers UUID;
  track_bible_study UUID;
  track_leadership UUID;
  track_mentorship UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.discipleship_tracks WHERE organization_id = org_id) THEN
    INSERT INTO public.discipleship_tracks (
      organization_id, name, description, category, duration, schedule, color, sort_order, is_default
    ) VALUES
      (
        org_id,
        'New Believers Class',
        'Foundational teachings for new Christians',
        'Foundation',
        '8 weeks',
        'Sundays, 9:00 AM',
        'blue',
        1,
        true
      )
    RETURNING id INTO track_new_believers;

    INSERT INTO public.discipleship_tracks (
      organization_id, name, description, category, duration, schedule, color, sort_order, is_default
    ) VALUES
      (
        org_id,
        'Bible Study Groups',
        'In-depth study of Scripture in small groups',
        'Growth',
        'Ongoing',
        'Wednesdays, 7:00 PM',
        'green',
        2,
        true
      )
    RETURNING id INTO track_bible_study;

    INSERT INTO public.discipleship_tracks (
      organization_id, name, description, category, duration, schedule, color, sort_order, is_default
    ) VALUES
      (
        org_id,
        'Leadership Development',
        'Training for future church leaders',
        'Leadership',
        '12 weeks',
        'Saturdays, 10:00 AM',
        'purple',
        3,
        true
      )
    RETURNING id INTO track_leadership;

    INSERT INTO public.discipleship_tracks (
      organization_id, name, description, category, duration, schedule, color, sort_order, is_default
    ) VALUES
      (
        org_id,
        'Mentorship Program',
        'One-on-one discipleship and spiritual guidance',
        'Mentorship',
        '6 months',
        'Flexible',
        'pink',
        4,
        true
      )
    RETURNING id INTO track_mentorship;

    INSERT INTO public.discipleship_milestones (track_id, name, description, sort_order) VALUES
      (track_new_believers, 'Complete intro reading', 'Read the foundational discipleship booklet', 1),
      (track_new_believers, 'Memorize key verses', 'Memorize salvation and assurance scriptures', 2),
      (track_new_believers, 'Attend all sessions', 'Attend each weekly class session', 3),
      (track_new_believers, 'Share your testimony', 'Present testimony to the class', 4);

    INSERT INTO public.discipleship_milestones (track_id, name, description, sort_order) VALUES
      (track_bible_study, 'Join a study group', 'Attend first small group meeting', 1),
      (track_bible_study, 'Complete book study', 'Finish the current book or series', 2),
      (track_bible_study, 'Lead a discussion', 'Facilitate one group discussion', 3),
      (track_bible_study, 'Apply weekly lesson', 'Log one workplace faith application', 4);

    INSERT INTO public.discipleship_milestones (track_id, name, description, sort_order) VALUES
      (track_leadership, 'Complete leadership modules', 'Finish all leadership training modules', 1),
      (track_leadership, 'Shadow a leader', 'Observe and assist an existing leader', 2),
      (track_leadership, 'Lead a project', 'Lead a small ministry or marketplace project', 3),
      (track_leadership, 'Receive commissioning', 'Commissioned for leadership role', 4),
      (track_leadership, 'Cohost a cell group', 'Apprenticeship phase: co-lead a cell group', 5);

    INSERT INTO public.discipleship_milestones (track_id, name, description, sort_order) VALUES
      (track_mentorship, 'Establish meeting rhythm', 'Set regular mentor-disciple meeting schedule', 1),
      (track_mentorship, 'Complete spiritual habits review', 'Review and practice core spiritual disciplines', 2),
      (track_mentorship, 'Workplace ethics discussion', 'Discuss ethical challenges at work', 3),
      (track_mentorship, 'Marketplace integration goal', 'Set and track a workplace faith goal', 4),
      (track_mentorship, 'Mentor readiness assessment', 'Evaluate readiness to disciple others', 5);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.seed_default_discipleship_tracks(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seed_default_discipleship_tracks(UUID) TO authenticated;
