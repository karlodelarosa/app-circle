BEGIN;

CREATE TABLE IF NOT EXISTS public.circle_person_badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  badge_type TEXT NOT NULL CHECK (badge_type IN ('discipleship')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','system_grandfathered')),
  note TEXT NOT NULL DEFAULT '',
  awarded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  awarded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, person_id, badge_type)
);

CREATE TABLE IF NOT EXISTS public.circle_leader_approvals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'approved' CHECK (status IN ('approved','revoked')),
  approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, person_id)
);

CREATE TABLE IF NOT EXISTS public.circle_account_transitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  old_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  new_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL CHECK (action IN ('generated_to_sheepcount','leadership_approved','badge_awarded','badge_revoked')),
  note TEXT NOT NULL DEFAULT '',
  performed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS circle_person_badges_person_idx
  ON public.circle_person_badges(organization_id, person_id);
CREATE INDEX IF NOT EXISTS circle_leader_approvals_status_idx
  ON public.circle_leader_approvals(organization_id, status);
CREATE INDEX IF NOT EXISTS circle_account_transitions_person_idx
  ON public.circle_account_transitions(organization_id, person_id, created_at DESC);

ALTER TABLE public.circle_person_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_leader_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_account_transitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Circle users read badges in their groups" ON public.circle_person_badges;
CREATE POLICY "Circle users read badges in their groups"
ON public.circle_person_badges FOR SELECT TO authenticated
USING (
  public.circle_is_org_admin(circle_person_badges.organization_id)
  OR EXISTS (
    SELECT 1
    FROM public.cell_group_members target_membership
    JOIN public.cell_group_members viewer_membership
      ON viewer_membership.cell_group_id = target_membership.cell_group_id
    JOIN public.circle_user_links viewer_link
      ON viewer_link.organization_id = circle_person_badges.organization_id
      AND viewer_link.person_id = viewer_membership.person_id
      AND viewer_link.user_id = auth.uid()
      AND viewer_link.status = 'active'
    WHERE target_membership.person_id = circle_person_badges.person_id
  )
);

DROP POLICY IF EXISTS "Admins read leader approvals" ON public.circle_leader_approvals;
CREATE POLICY "Admins read leader approvals"
ON public.circle_leader_approvals FOR SELECT TO authenticated
USING (public.circle_is_org_admin(circle_leader_approvals.organization_id));

DROP POLICY IF EXISTS "Admins read account transitions" ON public.circle_account_transitions;
CREATE POLICY "Admins read account transitions"
ON public.circle_account_transitions FOR SELECT TO authenticated
USING (public.circle_is_org_admin(circle_account_transitions.organization_id));

CREATE OR REPLACE FUNCTION public.get_circle_member_badges(p_cell_group_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.circle_can_access_group(p_cell_group_id) THEN
    RAISE EXCEPTION 'Circle access required';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'personId', member.person_id,
      'discipleshipBadge', badge.status = 'active',
      'badgeSource', badge.source,
      'badgeAwardedAt', badge.awarded_at,
      'leadershipStatus', approval.status
    ) ORDER BY person.last_name, person.first_name)
    FROM public.cell_group_members member
    JOIN public.people person ON person.id = member.person_id
    LEFT JOIN public.circle_person_badges badge
      ON badge.organization_id = person.organization_id
      AND badge.person_id = person.id
      AND badge.badge_type = 'discipleship'
    LEFT JOIN public.circle_leader_approvals approval
      ON approval.organization_id = person.organization_id
      AND approval.person_id = person.id
    WHERE member.cell_group_id = p_cell_group_id
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_member_account_statuses(p_cell_group_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_org UUID;
BEGIN
  SELECT organization_id INTO v_org FROM public.cell_groups WHERE id = p_cell_group_id;
  IF v_org IS NULL OR NOT (public.circle_is_org_admin(v_org) OR public.circle_can_lead_group(p_cell_group_id)) THEN
    RAISE EXCEPTION 'Leader access required';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'personId', member.person_id,
      'status', COALESCE(link.status, 'none'),
      'kind', link.account_kind,
      'loginId', link.login_id,
      'mustChangePassword', COALESCE(link.must_change_password, false),
      'transitions', CASE WHEN public.circle_is_org_admin(v_org) THEN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'action', transition.action,
          'note', transition.note,
          'createdAt', transition.created_at
        ) ORDER BY transition.created_at DESC)
        FROM public.circle_account_transitions transition
        WHERE transition.organization_id = v_org AND transition.person_id = member.person_id
      ), '[]'::jsonb) ELSE '[]'::jsonb END
    ) ORDER BY person.last_name, person.first_name)
    FROM public.cell_group_members member
    JOIN public.people person ON person.id = member.person_id
    LEFT JOIN public.circle_user_links link
      ON link.organization_id = person.organization_id AND link.person_id = person.id
    WHERE member.cell_group_id = p_cell_group_id
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_approved_leaders()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_org UUID;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.organization_members
  WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
  ORDER BY created_at LIMIT 1;
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organization admin access required'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'personId', person.id,
      'fullName', concat_ws(' ', person.first_name, person.last_name),
      'email', person.email
    ) ORDER BY person.last_name, person.first_name)
    FROM public.circle_leader_approvals approval
    JOIN public.people person ON person.id = approval.person_id
    JOIN public.circle_user_links link
      ON link.organization_id = approval.organization_id
      AND link.person_id = approval.person_id
      AND link.status = 'active'
      AND link.account_kind = 'existing'
    WHERE approval.organization_id = v_org
      AND approval.status = 'approved'
      AND person.status = 'Active'
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_circle_discipleship_badge(
  p_person_id UUID,
  p_active BOOLEAN,
  p_note TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_org UUID; v_action TEXT;
BEGIN
  SELECT organization_id INTO v_org FROM public.people WHERE id = p_person_id AND status = 'Active';
  IF v_org IS NULL OR NOT public.circle_is_org_admin(v_org) THEN
    RAISE EXCEPTION 'Organization admin access required';
  END IF;
  IF NOT p_active AND EXISTS (
    SELECT 1
    FROM public.cell_groups group_row
    LEFT JOIN public.cell_group_members membership
      ON membership.cell_group_id = group_row.id
      AND membership.person_id = p_person_id
      AND membership.role = 'Leader'
    WHERE group_row.organization_id = v_org
      AND group_row.status = 'active'
      AND (group_row.leader_person_id = p_person_id OR membership.id IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'Reassign or deactivate this person''s active Circle before revoking the badge';
  END IF;

  INSERT INTO public.circle_person_badges(
    organization_id, person_id, badge_type, status, source, note,
    awarded_by, awarded_at, revoked_by, revoked_at, updated_at
  ) VALUES (
    v_org, p_person_id, 'discipleship', CASE WHEN p_active THEN 'active' ELSE 'revoked' END,
    'manual', COALESCE(trim(p_note), ''),
    CASE WHEN p_active THEN auth.uid() ELSE NULL END, now(),
    CASE WHEN p_active THEN NULL ELSE auth.uid() END,
    CASE WHEN p_active THEN NULL ELSE now() END, now()
  ) ON CONFLICT (organization_id, person_id, badge_type) DO UPDATE SET
    status = excluded.status,
    source = 'manual',
    note = excluded.note,
    awarded_by = CASE WHEN p_active THEN auth.uid() ELSE circle_person_badges.awarded_by END,
    awarded_at = CASE WHEN p_active THEN now() ELSE circle_person_badges.awarded_at END,
    revoked_by = CASE WHEN p_active THEN NULL ELSE auth.uid() END,
    revoked_at = CASE WHEN p_active THEN NULL ELSE now() END,
    updated_at = now();

  IF NOT p_active THEN
    UPDATE public.circle_leader_approvals SET
      status = 'revoked', revoked_by = auth.uid(), revoked_at = now(), updated_at = now()
    WHERE organization_id = v_org AND person_id = p_person_id;
  END IF;
  v_action := CASE WHEN p_active THEN 'badge_awarded' ELSE 'badge_revoked' END;
  INSERT INTO public.circle_account_transitions(
    organization_id, person_id, action, note, performed_by
  ) VALUES (v_org, p_person_id, v_action, COALESCE(trim(p_note), ''), auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_circle_leader_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.leader_person_id IS NULL OR (TG_OP = 'UPDATE' AND NEW.leader_person_id IS NOT DISTINCT FROM OLD.leader_person_id) THEN
    RETURN NEW;
  END IF;
  IF NOT public.circle_is_org_admin(NEW.organization_id) THEN
    RAISE EXCEPTION 'Only organization administrators can assign a primary Circle leader';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.people person
    JOIN public.circle_leader_approvals approval
      ON approval.organization_id = person.organization_id
      AND approval.person_id = person.id AND approval.status = 'approved'
    JOIN public.circle_user_links link
      ON link.organization_id = person.organization_id
      AND link.person_id = person.id AND link.status = 'active' AND link.account_kind = 'existing'
    WHERE person.id = NEW.leader_person_id
      AND person.organization_id = NEW.organization_id
      AND person.status = 'Active'
  ) THEN
    RAISE EXCEPTION 'Choose an approved leader with a SheepCount account';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_circle_leader_assignment ON public.cell_groups;
CREATE TRIGGER enforce_circle_leader_assignment
BEFORE INSERT OR UPDATE OF leader_person_id ON public.cell_groups
FOR EACH ROW EXECUTE FUNCTION public.enforce_circle_leader_assignment();

CREATE OR REPLACE FUNCTION public.assign_circle_approved_leader(
  p_cell_group_id UUID,
  p_person_id UUID
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_org UUID; v_previous UUID;
BEGIN
  SELECT organization_id, leader_person_id INTO v_org, v_previous
  FROM public.cell_groups WHERE id = p_cell_group_id AND status = 'active';
  IF v_org IS NULL OR NOT public.circle_is_org_admin(v_org) THEN
    RAISE EXCEPTION 'Organization admin access required';
  END IF;
  UPDATE public.cell_groups SET leader_person_id = p_person_id WHERE id = p_cell_group_id;
  IF v_previous IS NOT NULL AND v_previous <> p_person_id THEN
    UPDATE public.cell_group_members SET role = 'Member'
    WHERE cell_group_id = p_cell_group_id AND person_id = v_previous;
  END IF;
  INSERT INTO public.cell_group_members(cell_group_id, person_id, role)
  VALUES (p_cell_group_id, p_person_id, 'Leader')
  ON CONFLICT (cell_group_id, person_id) DO UPDATE SET role = 'Leader';
END;
$$;

CREATE OR REPLACE FUNCTION public.promote_circle_leader(
  p_person_id UUID,
  p_new_user_id UUID,
  p_old_user_id UUID,
  p_created_new_user BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_org UUID; v_email TEXT; v_current public.circle_user_links%ROWTYPE;
BEGIN
  SELECT organization_id, lower(trim(email)) INTO v_org, v_email FROM public.people
  WHERE id = p_person_id AND status = 'Active' AND nullif(trim(email), '') IS NOT NULL;
  IF v_org IS NULL OR NOT public.circle_is_org_admin(v_org) THEN
    RAISE EXCEPTION 'Organization admin access required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.circle_person_badges
    WHERE organization_id = v_org AND person_id = p_person_id
      AND badge_type = 'discipleship' AND status = 'active'
  ) THEN RAISE EXCEPTION 'An active Discipleship badge is required'; END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.cell_group_members membership
    JOIN public.cell_groups group_row ON group_row.id = membership.cell_group_id
    WHERE membership.person_id = p_person_id
      AND group_row.organization_id = v_org
      AND group_row.status = 'active'
  ) THEN RAISE EXCEPTION 'The person must belong to an active Circle'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM auth.users target_user
    WHERE target_user.id = p_new_user_id
      AND lower(trim(target_user.email)) = v_email
  ) THEN RAISE EXCEPTION 'The SheepCount auth account must match the People email'; END IF;

  SELECT * INTO v_current FROM public.circle_user_links
  WHERE organization_id = v_org AND person_id = p_person_id;
  IF v_current.id IS NOT NULL AND p_old_user_id IS DISTINCT FROM v_current.user_id THEN
    RAISE EXCEPTION 'The member account changed; refresh and try again';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.circle_user_links
    WHERE organization_id = v_org AND user_id = p_new_user_id AND person_id <> p_person_id
  ) THEN RAISE EXCEPTION 'That SheepCount account is linked to another People record'; END IF;

  IF p_old_user_id IS NOT NULL AND p_old_user_id <> p_new_user_id THEN
    UPDATE public.organization_members SET status = 'inactive'
    WHERE organization_id = v_org AND user_id = p_old_user_id AND role <> 'admin';
  END IF;
  INSERT INTO public.organization_members(user_id, organization_id, role, status)
  VALUES (p_new_user_id, v_org, 'member', 'active')
  ON CONFLICT (user_id, organization_id) DO UPDATE SET
    status = 'active',
    role = CASE WHEN organization_members.role = 'admin' THEN 'admin' ELSE organization_members.role END;

  IF v_current.id IS NULL THEN
    INSERT INTO public.circle_user_links(
      user_id, organization_id, person_id, status, account_kind, login_id,
      must_change_password, provisioned_by, last_password_reset_at
    ) VALUES (
      p_new_user_id, v_org, p_person_id, 'active', 'existing', NULL,
      p_created_new_user, auth.uid(), CASE WHEN p_created_new_user THEN now() ELSE NULL END
    );
  ELSE
    UPDATE public.circle_user_links SET
      user_id = p_new_user_id, status = 'active', account_kind = 'existing', login_id = NULL,
      must_change_password = p_created_new_user, provisioned_by = auth.uid(),
      last_password_reset_at = CASE WHEN p_created_new_user THEN now() ELSE last_password_reset_at END,
      updated_at = now()
    WHERE id = v_current.id;
  END IF;

  INSERT INTO public.circle_leader_approvals(
    organization_id, person_id, status, approved_by, approved_at,
    revoked_by, revoked_at, updated_at
  ) VALUES (v_org, p_person_id, 'approved', auth.uid(), now(), NULL, NULL, now())
  ON CONFLICT (organization_id, person_id) DO UPDATE SET
    status = 'approved', approved_by = auth.uid(), approved_at = now(),
    revoked_by = NULL, revoked_at = NULL, updated_at = now();

  INSERT INTO public.circle_account_transitions(
    organization_id, person_id, old_user_id, new_user_id, action, note, performed_by
  ) VALUES (
    v_org, p_person_id, p_old_user_id, p_new_user_id,
    CASE WHEN p_old_user_id IS DISTINCT FROM p_new_user_id THEN 'generated_to_sheepcount' ELSE 'leadership_approved' END,
    CASE WHEN p_created_new_user THEN 'Created a standard SheepCount email account during promotion' ELSE 'Linked an existing SheepCount account during promotion' END,
    auth.uid()
  );
END;
$$;

-- Grandfather current leaders without changing their existing access.
WITH existing_leaders AS (
  SELECT organization_id, leader_person_id AS person_id
  FROM public.cell_groups
  WHERE status = 'active' AND leader_person_id IS NOT NULL
  UNION
  SELECT group_row.organization_id, membership.person_id
  FROM public.cell_group_members membership
  JOIN public.cell_groups group_row ON group_row.id = membership.cell_group_id
  WHERE group_row.status = 'active' AND membership.role = 'Leader'
)
INSERT INTO public.circle_person_badges(
  organization_id, person_id, badge_type, status, source, note
)
SELECT organization_id, person_id, 'discipleship', 'active', 'system_grandfathered',
  'Grandfathered when leadership qualifications were introduced'
FROM existing_leaders
ON CONFLICT (organization_id, person_id, badge_type) DO NOTHING;

WITH existing_leaders AS (
  SELECT organization_id, leader_person_id AS person_id
  FROM public.cell_groups
  WHERE status = 'active' AND leader_person_id IS NOT NULL
  UNION
  SELECT group_row.organization_id, membership.person_id
  FROM public.cell_group_members membership
  JOIN public.cell_groups group_row ON group_row.id = membership.cell_group_id
  WHERE group_row.status = 'active' AND membership.role = 'Leader'
)
INSERT INTO public.circle_leader_approvals(organization_id, person_id, status)
SELECT organization_id, person_id, 'approved' FROM existing_leaders
ON CONFLICT (organization_id, person_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.create_circle_group(
  p_name TEXT,
  p_description TEXT DEFAULT '',
  p_location TEXT DEFAULT '',
  p_leader_person_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_org_id UUID; v_group_id UUID;
BEGIN
  SELECT organization_id INTO v_org_id FROM public.organization_members
  WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
  ORDER BY created_at LIMIT 1;
  IF v_org_id IS NULL OR NOT public.circle_org_enabled(v_org_id) THEN
    RAISE EXCEPTION 'Organization admin access and Circles Pro are required';
  END IF;
  IF nullif(trim(p_name), '') IS NULL THEN RAISE EXCEPTION 'Circle name is required'; END IF;
  IF p_leader_person_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.people person
    JOIN public.circle_leader_approvals approval
      ON approval.organization_id = person.organization_id
      AND approval.person_id = person.id AND approval.status = 'approved'
    JOIN public.circle_user_links link
      ON link.organization_id = person.organization_id
      AND link.person_id = person.id AND link.status = 'active' AND link.account_kind = 'existing'
    WHERE person.id = p_leader_person_id
      AND person.organization_id = v_org_id AND person.status = 'Active'
  ) THEN RAISE EXCEPTION 'Choose an approved leader with a SheepCount account'; END IF;

  INSERT INTO public.cell_groups(organization_id, name, description, location, leader_person_id)
  VALUES (v_org_id, trim(p_name), trim(p_description), trim(p_location), p_leader_person_id)
  RETURNING id INTO v_group_id;
  INSERT INTO public.cell_group_members(cell_group_id, person_id, role)
  VALUES (v_group_id, p_leader_person_id, 'Leader')
  ON CONFLICT (cell_group_id, person_id) DO UPDATE SET role = 'Leader';
  RETURN v_group_id;
END;
$$;

-- Close legacy policies that allowed any organization member to write Circles.
DROP POLICY IF EXISTS "Org members can insert cell groups" ON public.cell_groups;
DROP POLICY IF EXISTS "Org members can update cell groups" ON public.cell_groups;
DROP POLICY IF EXISTS "Org members can view cell groups" ON public.cell_groups;
DROP POLICY IF EXISTS "Circle admins create groups" ON public.cell_groups;
CREATE POLICY "Circle admins create groups" ON public.cell_groups
FOR INSERT TO authenticated WITH CHECK (public.circle_is_org_admin(organization_id));
DROP POLICY IF EXISTS "Circle admins update groups" ON public.cell_groups;
CREATE POLICY "Circle admins update groups" ON public.cell_groups
FOR UPDATE TO authenticated USING (public.circle_is_org_admin(organization_id))
WITH CHECK (public.circle_is_org_admin(organization_id));
DROP POLICY IF EXISTS "Circle admins view all groups" ON public.cell_groups;
CREATE POLICY "Circle admins view all groups" ON public.cell_groups
FOR SELECT TO authenticated USING (public.circle_is_org_admin(organization_id));

REVOKE ALL ON FUNCTION public.get_circle_member_badges(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_circle_member_account_statuses(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_circle_approved_leaders() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_circle_discipleship_badge(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.promote_circle_leader(UUID, UUID, UUID, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_circle_approved_leader(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_circle_group(TEXT, TEXT, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_circle_member_badges(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_circle_member_account_statuses(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_circle_approved_leaders() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_circle_discipleship_badge(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.promote_circle_leader(UUID, UUID, UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_circle_approved_leader(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_circle_group(TEXT, TEXT, TEXT, UUID) TO authenticated;

COMMIT;
