-- Worker onboarding configuration and candidate lifecycle.

CREATE TABLE public.worker_onboarding_config (
  organization_id UUID PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
  course_id UUID NOT NULL REFERENCES public.training_courses(id) ON DELETE RESTRICT,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.worker_onboarding_candidates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  course_id UUID NOT NULL REFERENCES public.training_courses(id) ON DELETE RESTRICT,
  progress_id UUID NOT NULL REFERENCES public.person_course_progress(id) ON DELETE RESTRICT,
  target_ministry_id UUID NOT NULL REFERENCES public.work_ministries(id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'in_progress' CHECK (
    status IN ('in_progress', 'for_approval', 'ready_for_deployment', 'completed')
  ),
  return_note TEXT NOT NULL DEFAULT '',
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  approved_at TIMESTAMPTZ,
  deployed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  deployed_at TIMESTAMPTZ,
  deployed_membership_type TEXT CHECK (
    deployed_membership_type IS NULL OR
    deployed_membership_type IN ('Worker', 'Volunteer Worker')
  ),
  deployed_ministry_id UUID REFERENCES public.work_ministries(id) ON DELETE SET NULL,
  deployed_team_id UUID REFERENCES public.work_ministry_teams(id) ON DELETE SET NULL,
  deployed_role TEXT NOT NULL DEFAULT '',
  deployed_service_role TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, person_id),
  UNIQUE (progress_id)
);
CREATE INDEX worker_onboarding_candidates_org_status_idx
  ON public.worker_onboarding_candidates(organization_id, status);
CREATE INDEX worker_onboarding_candidates_target_ministry_idx
  ON public.worker_onboarding_candidates(target_ministry_id);
ALTER TABLE public.worker_onboarding_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.worker_onboarding_candidates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members can view worker onboarding config"
  ON public.worker_onboarding_config FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = worker_onboarding_config.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can view worker onboarding candidates"
  ON public.worker_onboarding_candidates FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = worker_onboarding_candidates.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE OR REPLACE FUNCTION public.set_worker_onboarding_course(
  p_organization_id UUID,
  p_course_id UUID
)
RETURNS public.worker_onboarding_config
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  result public.worker_onboarding_config;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.organization_id = p_organization_id
      AND om.user_id = auth.uid()
      AND om.role = 'admin'
      AND om.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.training_courses tc
    WHERE tc.id = p_course_id
      AND tc.organization_id = p_organization_id
      AND tc.is_active
      AND EXISTS (
        SELECT 1 FROM public.training_course_modules tcm
        WHERE tcm.course_id = tc.id
      )
  ) THEN
    RAISE EXCEPTION 'Select an active course with at least one module';
  END IF;

  INSERT INTO public.worker_onboarding_config (
    organization_id, course_id, updated_by, updated_at
  ) VALUES (
    p_organization_id, p_course_id, auth.uid(), now()
  )
  ON CONFLICT (organization_id) DO UPDATE SET
    course_id = EXCLUDED.course_id,
    updated_by = auth.uid(),
    updated_at = now()
  RETURNING * INTO result;

  RETURN result;
END;
$$;
CREATE OR REPLACE FUNCTION public.create_worker_onboarding_candidate(
  p_organization_id UUID,
  p_person_id UUID,
  p_target_ministry_id UUID
)
RETURNS public.worker_onboarding_candidates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  configured_course_id UUID;
  course_progress_id UUID;
  result public.worker_onboarding_candidates;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.organization_id = p_organization_id
      AND om.user_id = auth.uid()
      AND om.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Organization access required';
  END IF;

  SELECT course_id INTO configured_course_id
  FROM public.worker_onboarding_config
  WHERE organization_id = p_organization_id;

  IF configured_course_id IS NULL THEN
    RAISE EXCEPTION 'Worker onboarding course is not configured';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.training_courses tc
    WHERE tc.id = configured_course_id
      AND tc.organization_id = p_organization_id
      AND tc.is_active
      AND EXISTS (
        SELECT 1 FROM public.training_course_modules tcm
        WHERE tcm.course_id = tc.id
      )
  ) THEN
    RAISE EXCEPTION 'Worker onboarding course is not available';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.people p
    WHERE p.id = p_person_id
      AND p.organization_id = p_organization_id
      AND p.status = 'Active'
      AND p.membership_type IN ('Member', 'Attender')
  ) THEN
    RAISE EXCEPTION 'Candidate must be an active member or attender';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.work_ministries wm
    WHERE wm.id = p_target_ministry_id
      AND wm.organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'Target ministry does not belong to this organization';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.worker_onboarding_candidates woc
    WHERE woc.organization_id = p_organization_id
      AND woc.person_id = p_person_id
  ) THEN
    RAISE EXCEPTION 'This person already has a worker onboarding record';
  END IF;

  SELECT pcp.id INTO course_progress_id
  FROM public.person_course_progress pcp
  WHERE pcp.course_id = configured_course_id
    AND pcp.person_id = p_person_id;

  IF course_progress_id IS NULL THEN
    INSERT INTO public.person_course_progress (course_id, person_id)
    VALUES (configured_course_id, p_person_id)
    RETURNING id INTO course_progress_id;
  END IF;

  INSERT INTO public.worker_onboarding_candidates (
    organization_id,
    person_id,
    course_id,
    progress_id,
    target_ministry_id,
    created_by
  ) VALUES (
    p_organization_id,
    p_person_id,
    configured_course_id,
    course_progress_id,
    p_target_ministry_id,
    auth.uid()
  )
  RETURNING * INTO result;

  RETURN result;
END;
$$;
CREATE OR REPLACE FUNCTION public.update_worker_onboarding_target(
  p_candidate_id UUID,
  p_target_ministry_id UUID
)
RETURNS public.worker_onboarding_candidates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  candidate_org_id UUID;
  candidate_status TEXT;
  result public.worker_onboarding_candidates;
BEGIN
  SELECT organization_id, status
  INTO candidate_org_id, candidate_status
  FROM public.worker_onboarding_candidates
  WHERE id = p_candidate_id
  FOR UPDATE;

  IF candidate_org_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.organization_id = candidate_org_id
      AND om.user_id = auth.uid()
      AND om.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Candidate not found';
  END IF;

  IF candidate_status <> 'in_progress' THEN
    RAISE EXCEPTION 'Only in-progress candidates can change target ministry';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.work_ministries wm
    WHERE wm.id = p_target_ministry_id
      AND wm.organization_id = candidate_org_id
  ) THEN
    RAISE EXCEPTION 'Target ministry does not belong to this organization';
  END IF;

  UPDATE public.worker_onboarding_candidates
  SET target_ministry_id = p_target_ministry_id, updated_at = now()
  WHERE id = p_candidate_id
  RETURNING * INTO result;

  RETURN result;
END;
$$;
CREATE OR REPLACE FUNCTION public.submit_worker_onboarding_candidate(
  p_candidate_id UUID
)
RETURNS public.worker_onboarding_candidates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  candidate_org_id UUID;
  candidate_status TEXT;
  candidate_course_id UUID;
  candidate_progress_id UUID;
  result public.worker_onboarding_candidates;
BEGIN
  SELECT organization_id, status, course_id, progress_id
  INTO candidate_org_id, candidate_status, candidate_course_id, candidate_progress_id
  FROM public.worker_onboarding_candidates
  WHERE id = p_candidate_id
  FOR UPDATE;

  IF candidate_org_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.organization_id = candidate_org_id
      AND om.user_id = auth.uid()
      AND om.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Candidate not found';
  END IF;

  IF candidate_status <> 'in_progress' THEN
    RAISE EXCEPTION 'Candidate is not in progress';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.training_course_modules tcm
    WHERE tcm.course_id = candidate_course_id
  ) OR EXISTS (
    SELECT 1
    FROM public.training_course_modules tcm
    WHERE tcm.course_id = candidate_course_id
      AND NOT EXISTS (
        SELECT 1 FROM public.person_course_progress pcp
        WHERE pcp.id = candidate_progress_id
          AND tcm.id = ANY(pcp.completed_module_ids)
      )
  ) THEN
    RAISE EXCEPTION 'Complete every onboarding module before submitting';
  END IF;

  UPDATE public.worker_onboarding_candidates
  SET status = 'for_approval', return_note = '', updated_at = now()
  WHERE id = p_candidate_id
  RETURNING * INTO result;

  RETURN result;
END;
$$;
CREATE OR REPLACE FUNCTION public.approve_worker_onboarding_candidate(
  p_candidate_id UUID
)
RETURNS public.worker_onboarding_candidates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  candidate_org_id UUID;
  candidate_status TEXT;
  result public.worker_onboarding_candidates;
BEGIN
  SELECT organization_id, status INTO candidate_org_id, candidate_status
  FROM public.worker_onboarding_candidates WHERE id = p_candidate_id
  FOR UPDATE;

  IF candidate_org_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.organization_id = candidate_org_id
      AND om.user_id = auth.uid()
      AND om.role = 'admin'
      AND om.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF candidate_status <> 'for_approval' THEN
    RAISE EXCEPTION 'Candidate is not awaiting approval';
  END IF;

  UPDATE public.worker_onboarding_candidates
  SET status = 'ready_for_deployment', reviewed_by = auth.uid(),
      reviewed_at = now(), approved_at = now(), updated_at = now()
  WHERE id = p_candidate_id
  RETURNING * INTO result;
  RETURN result;
END;
$$;
CREATE OR REPLACE FUNCTION public.return_worker_onboarding_candidate(
  p_candidate_id UUID,
  p_return_note TEXT
)
RETURNS public.worker_onboarding_candidates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  candidate_org_id UUID;
  candidate_status TEXT;
  cleaned_note TEXT := trim(COALESCE(p_return_note, ''));
  result public.worker_onboarding_candidates;
BEGIN
  SELECT organization_id, status INTO candidate_org_id, candidate_status
  FROM public.worker_onboarding_candidates WHERE id = p_candidate_id
  FOR UPDATE;

  IF candidate_org_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.organization_id = candidate_org_id
      AND om.user_id = auth.uid()
      AND om.role = 'admin'
      AND om.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF candidate_status <> 'for_approval' THEN
    RAISE EXCEPTION 'Candidate is not awaiting approval';
  END IF;
  IF cleaned_note = '' OR char_length(cleaned_note) > 2000 THEN
    RAISE EXCEPTION 'Return note must contain 1 to 2000 characters';
  END IF;

  UPDATE public.worker_onboarding_candidates
  SET status = 'in_progress', return_note = cleaned_note,
      reviewed_by = auth.uid(), reviewed_at = now(), approved_at = NULL,
      updated_at = now()
  WHERE id = p_candidate_id
  RETURNING * INTO result;
  RETURN result;
END;
$$;
CREATE OR REPLACE FUNCTION public.deploy_worker_onboarding_candidate(
  p_candidate_id UUID,
  p_membership_type TEXT,
  p_ministry_id UUID,
  p_team_id UUID DEFAULT NULL,
  p_role TEXT DEFAULT 'Member',
  p_service_role TEXT DEFAULT ''
)
RETURNS public.worker_onboarding_candidates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  candidate_org_id UUID;
  candidate_person_id UUID;
  candidate_status TEXT;
  cleaned_role TEXT := trim(COALESCE(p_role, ''));
  cleaned_service_role TEXT := trim(COALESCE(p_service_role, ''));
  result public.worker_onboarding_candidates;
BEGIN
  SELECT organization_id, person_id, status
  INTO candidate_org_id, candidate_person_id, candidate_status
  FROM public.worker_onboarding_candidates WHERE id = p_candidate_id
  FOR UPDATE;

  IF candidate_org_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.organization_id = candidate_org_id
      AND om.user_id = auth.uid()
      AND om.role = 'admin'
      AND om.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF candidate_status <> 'ready_for_deployment' THEN
    RAISE EXCEPTION 'Candidate is not ready for deployment';
  END IF;
  IF p_membership_type NOT IN ('Worker', 'Volunteer Worker') THEN
    RAISE EXCEPTION 'Invalid worker membership type';
  END IF;
  IF cleaned_role = '' OR char_length(cleaned_role) > 100 OR
     char_length(cleaned_service_role) > 100 THEN
    RAISE EXCEPTION 'Role values are invalid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.work_ministries wm
    WHERE wm.id = p_ministry_id AND wm.organization_id = candidate_org_id
  ) THEN
    RAISE EXCEPTION 'Ministry does not belong to this organization';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.people p
    WHERE p.id = candidate_person_id
      AND p.organization_id = candidate_org_id
      AND p.status = 'Active'
      AND p.membership_type IN ('Member', 'Attender')
  ) THEN
    RAISE EXCEPTION 'Candidate is no longer an active member or attender';
  END IF;
  IF p_team_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.work_ministry_teams wmt
    WHERE wmt.id = p_team_id AND wmt.work_ministry_id = p_ministry_id
  ) THEN
    RAISE EXCEPTION 'Team does not belong to the selected ministry';
  END IF;

  INSERT INTO public.work_ministry_members (
    work_ministry_id, person_id, team_id, role, service_role
  ) VALUES (
    p_ministry_id, candidate_person_id, p_team_id, cleaned_role, cleaned_service_role
  )
  ON CONFLICT (work_ministry_id, person_id) DO UPDATE SET
    team_id = EXCLUDED.team_id,
    role = EXCLUDED.role,
    service_role = EXCLUDED.service_role;

  UPDATE public.people
  SET membership_type = p_membership_type::public.person_membership_type,
      evangelism_stage = 'Worker'::public.person_evangelism_stage,
      updated_at = now()
  WHERE id = candidate_person_id AND organization_id = candidate_org_id;

  UPDATE public.worker_onboarding_candidates
  SET status = 'completed', target_ministry_id = p_ministry_id,
      deployed_by = auth.uid(), deployed_at = now(),
      deployed_membership_type = p_membership_type,
      deployed_ministry_id = p_ministry_id, deployed_team_id = p_team_id,
      deployed_role = cleaned_role, deployed_service_role = cleaned_service_role,
      updated_at = now()
  WHERE id = p_candidate_id
  RETURNING * INTO result;
  RETURN result;
END;
$$;
CREATE OR REPLACE FUNCTION public.remove_worker_onboarding_candidate(
  p_candidate_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  candidate_org_id UUID;
  candidate_status TEXT;
BEGIN
  SELECT organization_id, status INTO candidate_org_id, candidate_status
  FROM public.worker_onboarding_candidates WHERE id = p_candidate_id
  FOR UPDATE;

  IF candidate_org_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.organization_id = candidate_org_id
      AND om.user_id = auth.uid()
      AND om.role = 'admin'
      AND om.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF candidate_status = 'completed' THEN
    RAISE EXCEPTION 'Completed onboarding records cannot be removed';
  END IF;

  DELETE FROM public.worker_onboarding_candidates WHERE id = p_candidate_id;
END;
$$;
REVOKE ALL ON FUNCTION public.set_worker_onboarding_course(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_worker_onboarding_candidate(UUID, UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_worker_onboarding_target(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_worker_onboarding_candidate(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_worker_onboarding_candidate(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.return_worker_onboarding_candidate(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.deploy_worker_onboarding_candidate(UUID, TEXT, UUID, UUID, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_worker_onboarding_candidate(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_worker_onboarding_course(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_worker_onboarding_candidate(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_worker_onboarding_target(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_worker_onboarding_candidate(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_worker_onboarding_candidate(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.return_worker_onboarding_candidate(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deploy_worker_onboarding_candidate(UUID, TEXT, UUID, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_worker_onboarding_candidate(UUID) TO authenticated;
