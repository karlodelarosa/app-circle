-- Harden entitlement RPCs: require org membership or platform admin before returning data.

CREATE OR REPLACE FUNCTION public.caller_can_access_org(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organization_members om
    WHERE om.organization_id = p_org_id
      AND om.user_id = auth.uid()
      AND om.status = 'active'
  )
  OR EXISTS (
    SELECT 1
    FROM public.platform_admins pa
    WHERE pa.user_id = auth.uid()
  );
$$;
REVOKE ALL ON FUNCTION public.caller_can_access_org(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.caller_can_access_org(UUID) FROM authenticated;
CREATE OR REPLACE FUNCTION public.org_has_feature(p_org_id UUID, p_feature_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN NOT public.caller_can_access_org(p_org_id) THEN false
    ELSE COALESCE(
      (
        SELECT (features ->> p_feature_key)::boolean
        FROM public.get_org_subscription_row(p_org_id)
      ),
      false
    )
  END;
$$;
CREATE OR REPLACE FUNCTION public.org_has_module_group(p_org_id UUID, p_group_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN NOT public.caller_can_access_org(p_org_id) THEN false
    ELSE COALESCE(
      (
        SELECT (modules -> 'groups' -> p_group_key ->> 'enabled')::boolean
        FROM public.get_org_subscription_row(p_org_id)
      ),
      false
    )
  END;
$$;
CREATE OR REPLACE FUNCTION public.org_has_module(p_org_id UUID, p_item_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  row_data RECORD;
  item_enabled BOOLEAN;
  group_key TEXT;
  group_enabled BOOLEAN;
BEGIN
  IF NOT public.caller_can_access_org(p_org_id) THEN
    RETURN false;
  END IF;

  SELECT * INTO row_data FROM public.get_org_subscription_row(p_org_id);
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  item_enabled := COALESCE((row_data.modules -> 'items' -> p_item_key ->> 'enabled')::boolean, false);
  IF NOT item_enabled THEN
    RETURN false;
  END IF;

  IF p_item_key = 'dashboard' THEN
    RETURN COALESCE((row_data.modules -> 'groups' -> 'dashboard' ->> 'enabled')::boolean, false);
  END IF;

  group_key := CASE p_item_key
    WHEN 'people' THEN 'people_membership'
    WHEN 'workers' THEN 'people_membership'
    WHEN 'households' THEN 'people_membership'
    WHEN 'water_baptism' THEN 'people_membership'
    WHEN 'life_groups' THEN 'groups_ministry'
    WHEN 'cell_groups' THEN 'groups_ministry'
    WHEN 'work_ministry' THEN 'groups_ministry'
    WHEN 'service_attendance' THEN 'attendance'
    WHEN 'event_attendance' THEN 'attendance'
    WHEN 'training' THEN 'development'
    WHEN 'discipleship' THEN 'development'
    WHEN 'bible_study' THEN 'development'
    WHEN 'programs' THEN 'development'
    WHEN 'leadership' THEN 'leadership'
    WHEN 'growth_track' THEN 'growth_track'
    WHEN 'properties' THEN 'operations'
    WHEN 'financial' THEN 'finance_projects'
    WHEN 'goal_projects' THEN 'finance_projects'
    WHEN 'church_goals' THEN 'ministry_planning'
    ELSE NULL
  END;

  IF group_key IS NULL THEN
    RETURN false;
  END IF;

  group_enabled := COALESCE((row_data.modules -> 'groups' -> group_key ->> 'enabled')::boolean, false);
  RETURN group_enabled;
END;
$$;
CREATE OR REPLACE FUNCTION public.get_org_entitlements(p_org_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  sub_row RECORD;
BEGIN
  IF NOT public.caller_can_access_org(p_org_id) THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT * INTO sub_row FROM public.get_org_subscription_row(p_org_id);
  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'plan_key', sub_row.plan_key,
    'limits', jsonb_build_object(
      'max_people', sub_row.max_people,
      'max_attendance_sessions', sub_row.max_attendance_sessions,
      'max_admin_seats', sub_row.max_admin_seats,
      'max_member_seats', sub_row.max_member_seats
    ),
    'usage', jsonb_build_object(
      'people', public.get_org_people_count(p_org_id),
      'attendance_sessions', public.get_org_attendance_session_count(p_org_id),
      'admin_seats', public.get_org_seat_count(p_org_id, 'admin'),
      'member_seats', public.get_org_seat_count(p_org_id, 'member')
    ),
    'modules', sub_row.modules,
    'features', sub_row.features
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.get_org_people_count(p_org_id UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COUNT(*)::int
  FROM public.people
  WHERE organization_id = p_org_id;
$$;
CREATE OR REPLACE FUNCTION public.get_org_attendance_session_count(p_org_id UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (
    (
      SELECT COUNT(*)::int
      FROM public.service_sessions ss
      JOIN public.service_types st ON st.id = ss.service_type_id
      WHERE ss.organization_id = p_org_id
        AND st.category = 'sunday'
    )
    +
    (
      SELECT COUNT(*)::int
      FROM public.life_group_sessions
      WHERE organization_id = p_org_id
    )
  );
$$;
CREATE OR REPLACE FUNCTION public.get_org_seat_count(p_org_id UUID, p_role TEXT)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COUNT(*)::int
  FROM public.organization_members
  WHERE organization_id = p_org_id
    AND status = 'active'
    AND role = p_role;
$$;
CREATE OR REPLACE FUNCTION public.org_can_add_person(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.caller_can_access_org(p_org_id)
    AND public.get_org_people_count(p_org_id) < (
      SELECT max_people FROM public.get_org_subscription_row(p_org_id)
    );
$$;
CREATE OR REPLACE FUNCTION public.org_can_add_attendance_session(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.caller_can_access_org(p_org_id)
    AND public.get_org_attendance_session_count(p_org_id) < (
      SELECT max_attendance_sessions FROM public.get_org_subscription_row(p_org_id)
    );
$$;
CREATE OR REPLACE FUNCTION public.org_can_add_member(p_org_id UUID, p_role TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  limits RECORD;
  current_count INT;
BEGIN
  IF NOT public.caller_can_access_org(p_org_id) THEN
    RETURN false;
  END IF;

  SELECT * INTO limits FROM public.get_org_subscription_row(p_org_id);
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF p_role = 'admin' THEN
    current_count := public.get_org_seat_count(p_org_id, 'admin');
    RETURN current_count < limits.max_admin_seats;
  ELSIF p_role = 'member' THEN
    current_count := public.get_org_seat_count(p_org_id, 'member');
    RETURN current_count < limits.max_member_seats;
  END IF;

  RETURN false;
END;
$$;
