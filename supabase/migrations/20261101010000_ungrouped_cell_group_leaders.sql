BEGIN;

ALTER TABLE public.circle_account_transitions
  DROP CONSTRAINT IF EXISTS circle_account_transitions_action_check;
ALTER TABLE public.circle_account_transitions
  ADD CONSTRAINT circle_account_transitions_action_check CHECK (
    action IN (
      'generated_to_sheepcount',
      'leadership_approved',
      'leadership_revoked',
      'badge_awarded',
      'badge_revoked',
      'login_replaced'
    )
  );

CREATE OR REPLACE FUNCTION public.circle_is_approved_leader(
  p_organization_id UUID,
  p_person_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.circle_leader_approvals approval
    JOIN public.people person
      ON person.id = approval.person_id
      AND person.organization_id = approval.organization_id
    WHERE approval.organization_id = p_organization_id
      AND approval.person_id = p_person_id
      AND approval.status = 'approved'
      AND person.status = 'Active'
  );
$$;

DROP FUNCTION IF EXISTS public.search_cell_group_leader_candidates(TEXT, INTEGER);
CREATE OR REPLACE FUNCTION public.search_cell_group_leader_candidates(
  p_organization_id UUID,
  p_query TEXT DEFAULT '',
  p_limit INTEGER DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org UUID;
  v_query TEXT := left(trim(COALESCE(p_query, '')), 100);
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
BEGIN
  SELECT p_organization_id INTO v_org
  WHERE EXISTS (
    SELECT 1 FROM public.organization_members membership
    WHERE membership.organization_id = p_organization_id
      AND membership.user_id = auth.uid()
    AND membership.role = 'admin'
    AND membership.status = 'active'
  );
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organization admin access required'; END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'personId', person.id,
      'fullName', concat_ws(' ', person.first_name, person.last_name),
      'email', COALESCE(person.email, ''),
      'phone', COALESCE(person.phone, '')
    ) ORDER BY person.last_name, person.first_name)
    FROM (
      SELECT person.*
      FROM public.people person
      WHERE person.organization_id = v_org
        AND person.status = 'Active'
        AND NOT EXISTS (
          SELECT 1 FROM public.circle_leader_approvals approval
          WHERE approval.organization_id = v_org
            AND approval.person_id = person.id
            AND approval.status = 'approved'
        )
        AND (
          v_query = ''
          OR person.first_name ILIKE '%' || v_query || '%'
          OR person.last_name ILIKE '%' || v_query || '%'
          OR COALESCE(person.email, '') ILIKE '%' || v_query || '%'
          OR COALESCE(person.phone, '') ILIKE '%' || v_query || '%'
        )
      ORDER BY person.last_name, person.first_name
      LIMIT v_limit
    ) person
  ), '[]'::jsonb);
END;
$$;

DROP FUNCTION IF EXISTS public.get_cell_group_leadership_roster();
CREATE OR REPLACE FUNCTION public.get_cell_group_leadership_roster(p_organization_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_org UUID;
BEGIN
  SELECT p_organization_id INTO v_org
  WHERE EXISTS (
    SELECT 1 FROM public.organization_members membership
    WHERE membership.organization_id = p_organization_id
      AND membership.user_id = auth.uid()
      AND membership.role = 'admin'
      AND membership.status = 'active'
  );
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organization admin access required'; END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'personId', person.id,
      'fullName', concat_ws(' ', person.first_name, person.last_name),
      'email', COALESCE(person.email, ''),
      'approvalStatus', approval.status,
      'activeGroupCount', (
        SELECT count(DISTINCT group_row.id)
        FROM public.cell_groups group_row
        LEFT JOIN public.cell_group_members group_membership
          ON group_membership.cell_group_id = group_row.id
          AND group_membership.person_id = person.id
          AND group_membership.role = 'Leader'
        WHERE group_row.organization_id = v_org
          AND group_row.status = 'active'
          AND (group_row.leader_person_id = person.id OR group_membership.id IS NOT NULL)
      ),
      'accountStatus', COALESCE(link.status, 'none'),
      'accountKind', link.account_kind,
      'loginId', link.login_id
    ) ORDER BY person.last_name, person.first_name)
    FROM public.circle_leader_approvals approval
    JOIN public.people person ON person.id = approval.person_id
    LEFT JOIN public.circle_user_links link
      ON link.organization_id = approval.organization_id
      AND link.person_id = approval.person_id
    WHERE approval.organization_id = v_org
      AND approval.status = 'approved'
      AND person.status = 'Active'
  ), '[]'::jsonb);
END;
$$;

DROP FUNCTION IF EXISTS public.set_cell_group_leader_approvals(UUID[], BOOLEAN);
CREATE OR REPLACE FUNCTION public.set_cell_group_leader_approvals(
  p_organization_id UUID,
  p_person_ids UUID[],
  p_approved BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org UUID;
  v_person_id UUID;
  v_name TEXT;
  v_existing_status TEXT;
  v_results JSONB := '[]'::jsonb;
BEGIN
  SELECT p_organization_id INTO v_org
  WHERE EXISTS (
    SELECT 1 FROM public.organization_members membership
    WHERE membership.organization_id = p_organization_id
      AND membership.user_id = auth.uid()
      AND membership.role = 'admin'
      AND membership.status = 'active'
  );
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organization admin access required'; END IF;
  IF COALESCE(cardinality(p_person_ids), 0) = 0 OR cardinality(p_person_ids) > 100 THEN
    RAISE EXCEPTION 'Choose between 1 and 100 people';
  END IF;

  FOR v_person_id IN SELECT DISTINCT unnest(p_person_ids)
  LOOP
    SELECT concat_ws(' ', person.first_name, person.last_name)
    INTO v_name
    FROM public.people person
    WHERE person.id = v_person_id
      AND person.organization_id = v_org
      AND (NOT p_approved OR person.status = 'Active');

    IF v_name IS NULL THEN
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'personId', v_person_id, 'ok', false,
        'message', 'Person is unavailable in this organization'
      ));
      CONTINUE;
    END IF;

    IF NOT p_approved AND EXISTS (
      SELECT 1
      FROM public.cell_groups group_row
      LEFT JOIN public.cell_group_members group_membership
        ON group_membership.cell_group_id = group_row.id
        AND group_membership.person_id = v_person_id
        AND group_membership.role = 'Leader'
      WHERE group_row.organization_id = v_org
        AND group_row.status = 'active'
        AND (group_row.leader_person_id = v_person_id OR group_membership.id IS NOT NULL)
    ) THEN
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'personId', v_person_id, 'fullName', v_name, 'ok', false,
        'message', 'Reassign this person''s active Cell Group before revoking leadership'
      ));
      CONTINUE;
    END IF;

    SELECT approval.status INTO v_existing_status
    FROM public.circle_leader_approvals approval
    WHERE approval.organization_id = v_org AND approval.person_id = v_person_id;

    INSERT INTO public.circle_leader_approvals(
      organization_id, person_id, status, approved_by, approved_at,
      revoked_by, revoked_at, updated_at
    ) VALUES (
      v_org, v_person_id, CASE WHEN p_approved THEN 'approved' ELSE 'revoked' END,
      CASE WHEN p_approved THEN auth.uid() ELSE NULL END, now(),
      CASE WHEN p_approved THEN NULL ELSE auth.uid() END,
      CASE WHEN p_approved THEN NULL ELSE now() END, now()
    ) ON CONFLICT (organization_id, person_id) DO UPDATE SET
      status = excluded.status,
      approved_by = CASE WHEN p_approved THEN auth.uid() ELSE circle_leader_approvals.approved_by END,
      approved_at = CASE WHEN p_approved THEN now() ELSE circle_leader_approvals.approved_at END,
      revoked_by = CASE WHEN p_approved THEN NULL ELSE auth.uid() END,
      revoked_at = CASE WHEN p_approved THEN NULL ELSE now() END,
      updated_at = now();

    IF v_existing_status IS DISTINCT FROM CASE WHEN p_approved THEN 'approved' ELSE 'revoked' END THEN
      INSERT INTO public.circle_account_transitions(
        organization_id, person_id, action, note, performed_by
      ) VALUES (
        v_org, v_person_id,
        CASE WHEN p_approved THEN 'leadership_approved' ELSE 'leadership_revoked' END,
        CASE WHEN p_approved
          THEN 'Approved as a Cell Group Leader without requiring a group assignment'
          ELSE 'Cell Group Leader approval revoked'
        END,
        auth.uid()
      );
    END IF;

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'personId', v_person_id, 'fullName', v_name, 'ok', true,
      'status', CASE WHEN p_approved THEN 'approved' ELSE 'revoked' END,
      'unchanged', v_existing_status IS NOT DISTINCT FROM CASE WHEN p_approved THEN 'approved' ELSE 'revoked' END
    ));
  END LOOP;
  RETURN v_results;
END;
$$;

DROP FUNCTION IF EXISTS public.get_circle_approved_leaders();
CREATE OR REPLACE FUNCTION public.get_circle_approved_leaders(p_organization_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_org UUID;
BEGIN
  SELECT p_organization_id INTO v_org
  WHERE EXISTS (
    SELECT 1 FROM public.organization_members membership
    WHERE membership.organization_id = p_organization_id
      AND membership.user_id = auth.uid()
      AND membership.role = 'admin'
      AND membership.status = 'active'
  );
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organization admin access required'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'personId', person.id,
      'fullName', concat_ws(' ', person.first_name, person.last_name),
      'email', COALESCE(person.email, ''),
      'accountStatus', COALESCE(link.status, 'none'),
      'accountKind', link.account_kind,
      'activeGroupCount', (
        SELECT count(DISTINCT group_row.id)
        FROM public.cell_groups group_row
        LEFT JOIN public.cell_group_members group_membership
          ON group_membership.cell_group_id = group_row.id
          AND group_membership.person_id = person.id
          AND group_membership.role = 'Leader'
        WHERE group_row.organization_id = v_org
          AND group_row.status = 'active'
          AND (group_row.leader_person_id = person.id OR group_membership.id IS NOT NULL)
      )
    ) ORDER BY person.last_name, person.first_name)
    FROM public.circle_leader_approvals approval
    JOIN public.people person ON person.id = approval.person_id
    LEFT JOIN public.circle_user_links link
      ON link.organization_id = approval.organization_id
      AND link.person_id = approval.person_id
    WHERE approval.organization_id = v_org
      AND approval.status = 'approved'
      AND person.status = 'Active'
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_circle_leader_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.leader_person_id IS NULL OR (TG_OP = 'UPDATE' AND NEW.leader_person_id IS NOT DISTINCT FROM OLD.leader_person_id) THEN
    RETURN NEW;
  END IF;
  IF NOT public.circle_is_approved_leader(NEW.organization_id, NEW.leader_person_id) THEN
    RAISE EXCEPTION 'Choose an approved Cell Group Leader';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_circle_group(
  p_name TEXT,
  p_description TEXT DEFAULT '',
  p_location TEXT DEFAULT '',
  p_leader_person_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org_id UUID;
  v_group_id UUID;
  v_person_id UUID;
  v_is_admin BOOLEAN := false;
  v_leader_id UUID;
BEGIN
  SELECT membership.organization_id, membership.role = 'admin'
  INTO v_org_id, v_is_admin
  FROM public.organization_members membership
  WHERE membership.user_id = auth.uid() AND membership.status = 'active'
  ORDER BY (membership.role = 'admin') DESC, membership.created_at
  LIMIT 1;
  IF v_org_id IS NULL OR NOT public.circle_org_enabled(v_org_id) THEN
    RAISE EXCEPTION 'An active Circles organization is required';
  END IF;
  IF nullif(trim(p_name), '') IS NULL THEN RAISE EXCEPTION 'Circle name is required'; END IF;

  IF v_is_admin THEN
    v_leader_id := p_leader_person_id;
    IF v_leader_id IS NULL OR NOT public.circle_is_approved_leader(v_org_id, v_leader_id) THEN
      RAISE EXCEPTION 'Choose an approved Cell Group Leader';
    END IF;
  ELSE
    SELECT link.person_id INTO v_person_id
    FROM public.circle_user_links link
    WHERE link.organization_id = v_org_id
      AND link.user_id = auth.uid()
      AND link.status = 'active'
    LIMIT 1;
    IF v_person_id IS NULL OR NOT public.circle_is_approved_leader(v_org_id, v_person_id) THEN
      RAISE EXCEPTION 'Cell Group Leader approval is required';
    END IF;
    IF p_leader_person_id IS NOT NULL AND p_leader_person_id <> v_person_id THEN
      RAISE EXCEPTION 'Leaders can create a Circle only for themselves';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM public.cell_groups group_row
      LEFT JOIN public.cell_group_members group_membership
        ON group_membership.cell_group_id = group_row.id
        AND group_membership.person_id = v_person_id
        AND group_membership.role = 'Leader'
      WHERE group_row.organization_id = v_org_id
        AND group_row.status = 'active'
        AND (group_row.leader_person_id = v_person_id OR group_membership.id IS NOT NULL)
    ) THEN
      RAISE EXCEPTION 'Only the first Circle can be created without an administrator';
    END IF;
    v_leader_id := v_person_id;
  END IF;

  INSERT INTO public.cell_groups(organization_id, name, description, location, leader_person_id)
  VALUES (v_org_id, trim(p_name), trim(COALESCE(p_description, '')), trim(COALESCE(p_location, '')), v_leader_id)
  RETURNING id INTO v_group_id;
  INSERT INTO public.cell_group_members(cell_group_id, person_id, role)
  VALUES (v_group_id, v_leader_id, 'Leader')
  ON CONFLICT (cell_group_id, person_id) DO UPDATE SET role = 'Leader';
  RETURN v_group_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_circle_context()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user UUID := auth.uid();
  v_org UUID;
  v_person UUID;
  v_admin BOOLEAN := false;
  v_approved_leader BOOLEAN := false;
  v_result JSONB;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT membership.organization_id, membership.role = 'admin'
  INTO v_org, v_admin
  FROM public.organization_members membership
  WHERE membership.user_id = v_user AND membership.status = 'active'
  ORDER BY (membership.role = 'admin') DESC, membership.created_at
  LIMIT 1;
  IF v_org IS NULL THEN RAISE EXCEPTION 'No active SheepCount organization is linked to this account'; END IF;

  SELECT link.person_id INTO v_person
  FROM public.circle_user_links link
  WHERE link.organization_id = v_org AND link.user_id = v_user AND link.status = 'active'
  LIMIT 1;
  v_approved_leader := public.circle_is_approved_leader(v_org, v_person);

  SELECT jsonb_build_object(
    'organization', jsonb_build_object(
      'id', organization.id, 'name', organization.name, 'slug', organization.slug,
      'image', organization.image, 'status', organization.status
    ),
    'circlesEnabled', true,
    'isAdmin', v_admin,
    'isApprovedLeader', v_approved_leader,
    'personId', v_person,
    'profile', jsonb_build_object(
      'id', profile.id, 'firstName', profile.first_name,
      'lastName', profile.last_name, 'avatarUrl', profile.avatar_url
    ),
    'groups', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', group_row.id, 'name', group_row.name,
        'description', group_row.description, 'location', group_row.location,
        'leaderPersonId', group_row.leader_person_id, 'status', group_row.status,
        'role', CASE
          WHEN v_admin THEN 'admin'
          WHEN group_membership.role = 'Leader' OR group_row.leader_person_id = v_person THEN 'leader'
          ELSE 'member'
        END
      ) ORDER BY group_row.name)
      FROM public.cell_groups group_row
      LEFT JOIN public.cell_group_members group_membership
        ON group_membership.cell_group_id = group_row.id AND group_membership.person_id = v_person
      WHERE group_row.organization_id = organization.id
        AND group_row.status = 'active'
        AND (v_admin OR group_membership.id IS NOT NULL OR group_row.leader_person_id = v_person)
    ), '[]'::jsonb)
  ) INTO v_result
  FROM public.organizations organization
  LEFT JOIN public.profiles profile ON profile.id = v_user
  WHERE organization.id = v_org;
  RETURN v_result;
END;
$$;

-- A Ministry Lens approval can enter the established Circles
-- credential-promotion flow. Credential mechanics remain owned by Circles.
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
  IF NOT public.circle_is_approved_leader(v_org, p_person_id) THEN
    RAISE EXCEPTION 'Cell Group Leader approval is required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM auth.users target_user
    WHERE target_user.id = p_new_user_id AND lower(trim(target_user.email)) = v_email
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

REVOKE ALL ON FUNCTION public.circle_is_approved_leader(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.search_cell_group_leader_candidates(UUID, TEXT, INTEGER) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_cell_group_leadership_roster(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_cell_group_leader_approvals(UUID, UUID[], BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_circle_approved_leaders(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_cell_group_leader_candidates(UUID, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cell_group_leadership_roster(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_cell_group_leader_approvals(UUID, UUID[], BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_circle_approved_leaders(UUID) TO authenticated;

COMMIT;
