-- Subscription plan templates, per-org overrides, entitlements, audit logs, and enforcement

-- ---------------------------------------------------------------------------
-- 1. subscription_plans
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.subscription_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  max_people INT NOT NULL DEFAULT 2500 CHECK (max_people > 0),
  max_attendance_sessions INT NOT NULL DEFAULT 2500 CHECK (max_attendance_sessions > 0),
  max_admin_seats INT NOT NULL DEFAULT 1 CHECK (max_admin_seats > 0),
  max_member_seats INT NOT NULL DEFAULT 2 CHECK (max_member_seats >= 0),
  modules JSONB NOT NULL DEFAULT '{}'::jsonb,
  features JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone authenticated can view active subscription plans" ON public.subscription_plans;
CREATE POLICY "Anyone authenticated can view active subscription plans"
  ON public.subscription_plans FOR SELECT
  TO authenticated
  USING (
    is_active = true
    OR EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS "Platform admins can manage subscription plans" ON public.subscription_plans;
CREATE POLICY "Platform admins can manage subscription plans"
  ON public.subscription_plans FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  );
-- ---------------------------------------------------------------------------
-- 2. Extend subscriptions
-- ---------------------------------------------------------------------------

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS plan_key TEXT REFERENCES public.subscription_plans(key),
  ADD COLUMN IF NOT EXISTS override_max_people INT CHECK (override_max_people IS NULL OR override_max_people > 0),
  ADD COLUMN IF NOT EXISTS override_max_attendance_sessions INT CHECK (override_max_attendance_sessions IS NULL OR override_max_attendance_sessions > 0),
  ADD COLUMN IF NOT EXISTS override_max_admin_seats INT CHECK (override_max_admin_seats IS NULL OR override_max_admin_seats > 0),
  ADD COLUMN IF NOT EXISTS override_max_member_seats INT CHECK (override_max_member_seats IS NULL OR override_max_member_seats >= 0),
  ADD COLUMN IF NOT EXISTS module_overrides JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS features_override JSONB NOT NULL DEFAULT '{}'::jsonb;
-- ---------------------------------------------------------------------------
-- 3. organization_audit_logs
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.organization_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL CHECK (action IN ('create', 'update', 'delete')),
  entity_type TEXT NOT NULL DEFAULT 'person',
  entity_id UUID,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS organization_audit_logs_organization_id_idx
  ON public.organization_audit_logs(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS organization_audit_logs_entity_id_idx
  ON public.organization_audit_logs(entity_id);
ALTER TABLE public.organization_audit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Platform admins can view all audit logs" ON public.organization_audit_logs;
CREATE POLICY "Platform admins can view all audit logs"
  ON public.organization_audit_logs FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  );
-- ---------------------------------------------------------------------------
-- 4. Seed plan templates
-- ---------------------------------------------------------------------------

INSERT INTO public.subscription_plans (key, name, max_people, max_attendance_sessions, max_admin_seats, max_member_seats, modules, features)
VALUES
(
  'basic',
  'Basic',
  2500,
  2500,
  1,
  2,
  '{
    "groups": {
      "dashboard": { "enabled": true },
      "people_membership": { "enabled": true },
      "groups_ministry": { "enabled": true },
      "attendance": { "enabled": true },
      "development": { "enabled": true },
      "leadership": { "enabled": true },
      "growth_track": { "enabled": false },
      "operations": { "enabled": false },
      "finance_projects": { "enabled": false }
    },
    "items": {
      "dashboard": { "enabled": true },
      "people": { "enabled": true },
      "workers": { "enabled": true },
      "households": { "enabled": true },
      "water_baptism": { "enabled": false },
      "life_groups": { "enabled": true },
      "cell_groups": { "enabled": true },
      "work_ministry": { "enabled": true },
      "service_attendance": { "enabled": true },
      "event_attendance": { "enabled": true },
      "training": { "enabled": true },
      "discipleship": { "enabled": true },
      "bible_study": { "enabled": true },
      "programs": { "enabled": true },
      "leadership": { "enabled": true },
      "growth_track": { "enabled": false },
      "properties": { "enabled": false },
      "financial": { "enabled": false },
      "goal_projects": { "enabled": false },
      "church_goals": { "enabled": false }
    }
  }'::jsonb,
  '{ "audit_trail": false }'::jsonb
),
(
  'pro',
  'Pro',
  2500,
  2500,
  1,
  2,
  '{
    "groups": {
      "dashboard": { "enabled": true },
      "people_membership": { "enabled": true },
      "groups_ministry": { "enabled": true },
      "attendance": { "enabled": true },
      "development": { "enabled": true },
      "leadership": { "enabled": true },
      "growth_track": { "enabled": true },
      "operations": { "enabled": true },
      "finance_projects": { "enabled": true }
    },
    "items": {
      "dashboard": { "enabled": true },
      "people": { "enabled": true },
      "workers": { "enabled": true },
      "households": { "enabled": true },
      "water_baptism": { "enabled": false },
      "life_groups": { "enabled": true },
      "cell_groups": { "enabled": true },
      "work_ministry": { "enabled": true },
      "service_attendance": { "enabled": true },
      "event_attendance": { "enabled": true },
      "training": { "enabled": true },
      "discipleship": { "enabled": true },
      "bible_study": { "enabled": true },
      "programs": { "enabled": true },
      "leadership": { "enabled": true },
      "growth_track": { "enabled": true },
      "properties": { "enabled": true },
      "financial": { "enabled": true },
      "goal_projects": { "enabled": true },
      "church_goals": { "enabled": true }
    }
  }'::jsonb,
  '{ "audit_trail": true }'::jsonb
)
ON CONFLICT (key) DO NOTHING;
-- ---------------------------------------------------------------------------
-- 5. Data migration
-- ---------------------------------------------------------------------------

UPDATE public.subscriptions
SET
  plan_key = CASE
    WHEN plan IN ('pro', 'Pro') THEN 'pro'
    ELSE 'basic'
  END,
  plan = CASE
    WHEN plan IN ('pro', 'Pro') THEN 'pro'
    ELSE 'basic'
  END
WHERE plan_key IS NULL OR plan IN ('standard', 'Standard');
UPDATE public.organizations
SET plan = CASE
  WHEN plan IN ('pro', 'Pro') THEN 'pro'
  ELSE 'basic'
END
WHERE plan IN ('standard', 'Standard') OR plan IS NULL;
UPDATE public.organizations o
SET plan = s.plan_key
FROM public.subscriptions s
WHERE s.organization_id = o.id
  AND s.plan_key IS NOT NULL
  AND o.plan IS DISTINCT FROM s.plan_key;
UPDATE public.subscriptions s
SET module_overrides = COALESCE(s.module_overrides, '{}'::jsonb) || jsonb_build_object(
  'items', jsonb_build_object(
    'water_baptism', jsonb_build_object('enabled', true)
  )
)
FROM public.organizations o
WHERE s.organization_id = o.id
  AND COALESCE(o.settings ->> 'waterBaptismEnabled', 'false') = 'true';
UPDATE public.subscriptions
SET plan_key = 'basic', plan = 'basic'
WHERE plan_key IS NULL;
ALTER TABLE public.subscriptions
  ALTER COLUMN plan_key SET NOT NULL,
  ALTER COLUMN plan_key SET DEFAULT 'basic';
ALTER TABLE public.organizations
  ALTER COLUMN plan SET DEFAULT 'basic';
-- ---------------------------------------------------------------------------
-- 6. JSON merge helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.merge_jsonb_objects(base JSONB, patch JSONB)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(base, '{}'::jsonb) || COALESCE(patch, '{}'::jsonb);
$$;
CREATE OR REPLACE FUNCTION public.merge_module_config(base JSONB, overrides JSONB)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  result JSONB := COALESCE(base, '{"groups": {}, "items": {}}'::jsonb);
  group_key TEXT;
  item_key TEXT;
  group_patch JSONB;
  item_patch JSONB;
BEGIN
  group_patch := COALESCE(overrides -> 'groups', '{}'::jsonb);
  item_patch := COALESCE(overrides -> 'items', '{}'::jsonb);

  FOR group_key IN SELECT jsonb_object_keys(group_patch)
  LOOP
    result := jsonb_set(
      result,
      ARRAY['groups', group_key],
      COALESCE(result -> 'groups' -> group_key, '{}'::jsonb) || (group_patch -> group_key),
      true
    );
  END LOOP;

  FOR item_key IN SELECT jsonb_object_keys(item_patch)
  LOOP
    result := jsonb_set(
      result,
      ARRAY['items', item_key],
      COALESCE(result -> 'items' -> item_key, '{}'::jsonb) || (item_patch -> item_key),
      true
    );
  END LOOP;

  RETURN result;
END;
$$;
-- ---------------------------------------------------------------------------
-- 7. Usage counters
-- ---------------------------------------------------------------------------

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
-- ---------------------------------------------------------------------------
-- 8. Resolved limits and features
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_org_subscription_row(p_org_id UUID)
RETURNS TABLE (
  plan_key TEXT,
  max_people INT,
  max_attendance_sessions INT,
  max_admin_seats INT,
  max_member_seats INT,
  modules JSONB,
  features JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    sp.key,
    COALESCE(s.override_max_people, sp.max_people),
    COALESCE(s.override_max_attendance_sessions, sp.max_attendance_sessions),
    COALESCE(s.override_max_admin_seats, sp.max_admin_seats),
    COALESCE(s.override_max_member_seats, sp.max_member_seats),
    public.merge_module_config(sp.modules, s.module_overrides),
    public.merge_jsonb_objects(sp.features, s.features_override)
  FROM public.subscriptions s
  JOIN public.subscription_plans sp ON sp.key = s.plan_key
  WHERE s.organization_id = p_org_id;
$$;
CREATE OR REPLACE FUNCTION public.org_has_feature(p_org_id UUID, p_feature_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (
      SELECT (features ->> p_feature_key)::boolean
      FROM public.get_org_subscription_row(p_org_id)
    ),
    false
  );
$$;
CREATE OR REPLACE FUNCTION public.org_has_module_group(p_org_id UUID, p_group_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (
      SELECT (modules -> 'groups' -> p_group_key ->> 'enabled')::boolean
      FROM public.get_org_subscription_row(p_org_id)
    ),
    false
  );
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
  group_key TEXT;
  group_enabled BOOLEAN;
  item_enabled BOOLEAN;
BEGIN
  SELECT * INTO row_data FROM public.get_org_subscription_row(p_org_id);
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  item_enabled := COALESCE((row_data.modules -> 'items' -> p_item_key ->> 'enabled')::boolean, false);
  IF NOT item_enabled THEN
    RETURN false;
  END IF;

  -- Dashboard is a standalone item/group
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
    WHEN 'church_goals' THEN 'finance_projects'
    ELSE NULL
  END;

  IF group_key IS NULL THEN
    RETURN false;
  END IF;

  group_enabled := COALESCE((row_data.modules -> 'groups' -> group_key ->> 'enabled')::boolean, false);
  RETURN group_enabled;
END;
$$;
CREATE OR REPLACE FUNCTION public.org_can_add_person(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.get_org_people_count(p_org_id) < (
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
  SELECT public.get_org_attendance_session_count(p_org_id) < (
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
GRANT EXECUTE ON FUNCTION public.get_org_entitlements(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_has_module(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_has_module_group(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_has_feature(UUID, TEXT) TO authenticated;
DROP POLICY IF EXISTS "Org members can view audit logs when feature enabled" ON public.organization_audit_logs;
CREATE POLICY "Org members can view audit logs when feature enabled"
  ON public.organization_audit_logs FOR SELECT
  USING (
    public.is_org_member(organization_id)
    AND public.org_has_feature(organization_id, 'audit_trail')
  );
-- ---------------------------------------------------------------------------
-- 9. Enforcement triggers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_people_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NOT public.org_can_add_person(NEW.organization_id) THEN
    RAISE EXCEPTION 'People limit reached for this organization';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS enforce_people_limit_before_insert ON public.people;
CREATE TRIGGER enforce_people_limit_before_insert
  BEFORE INSERT ON public.people
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_people_limit();
CREATE OR REPLACE FUNCTION public.enforce_attendance_session_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NOT public.org_can_add_attendance_session(NEW.organization_id) THEN
    RAISE EXCEPTION 'Attendance session limit reached for this organization';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS enforce_service_session_limit_before_insert ON public.service_sessions;
CREATE TRIGGER enforce_service_session_limit_before_insert
  BEFORE INSERT ON public.service_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_attendance_session_limit();
DROP TRIGGER IF EXISTS enforce_life_group_session_limit_before_insert ON public.life_group_sessions;
CREATE TRIGGER enforce_life_group_session_limit_before_insert
  BEFORE INSERT ON public.life_group_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_attendance_session_limit();
-- ---------------------------------------------------------------------------
-- 10. People audit log trigger (Pro / audit_trail feature only)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.audit_people_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org_id UUID;
  v_person_name TEXT;
  v_changes JSONB := '{}'::jsonb;
  v_key TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_org_id := OLD.organization_id;
    v_person_name := trim(concat_ws(' ', OLD.first_name, OLD.middle_name, OLD.last_name));
  ELSE
    v_org_id := NEW.organization_id;
    v_person_name := trim(concat_ws(' ', NEW.first_name, NEW.middle_name, NEW.last_name));
  END IF;

  IF NOT public.org_has_feature(v_org_id, 'audit_trail') THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    FOR v_key IN
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'people'
        AND column_name NOT IN ('id', 'organization_id', 'created_at', 'updated_at')
    LOOP
      IF to_jsonb(OLD) -> v_key IS DISTINCT FROM to_jsonb(NEW) -> v_key THEN
        v_changes := v_changes || jsonb_build_object(
          v_key,
          jsonb_build_object(
            'from', to_jsonb(OLD) -> v_key,
            'to', to_jsonb(NEW) -> v_key
          )
        );
      END IF;
    END LOOP;

    IF v_changes = '{}'::jsonb THEN
      RETURN NEW;
    END IF;

    INSERT INTO public.organization_audit_logs (
      organization_id,
      actor_user_id,
      action,
      entity_type,
      entity_id,
      metadata
    ) VALUES (
      v_org_id,
      auth.uid(),
      'update',
      'person',
      NEW.id,
      jsonb_build_object('person_name', v_person_name, 'changes', v_changes)
    );

    RETURN NEW;
  ELSIF TG_OP = 'INSERT' THEN
    INSERT INTO public.organization_audit_logs (
      organization_id,
      actor_user_id,
      action,
      entity_type,
      entity_id,
      metadata
    ) VALUES (
      v_org_id,
      auth.uid(),
      'create',
      'person',
      NEW.id,
      jsonb_build_object('person_name', v_person_name)
    );
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.organization_audit_logs (
      organization_id,
      actor_user_id,
      action,
      entity_type,
      entity_id,
      metadata
    ) VALUES (
      v_org_id,
      auth.uid(),
      'delete',
      'person',
      OLD.id,
      jsonb_build_object('person_name', v_person_name)
    );
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS audit_people_changes_trigger ON public.people;
CREATE TRIGGER audit_people_changes_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.people
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_people_changes();
-- ---------------------------------------------------------------------------
-- 11. Update setup_organization
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.setup_organization(org_name TEXT, org_slug TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  new_org_id UUID;
  slug_base TEXT;
  final_slug TEXT;
  current_user_id UUID;
BEGIN
  current_user_id := auth.uid();
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.organization_members
    WHERE user_id = current_user_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'User already belongs to an organization';
  END IF;

  slug_base := COALESCE(
    NULLIF(trim(org_slug), ''),
    lower(regexp_replace(trim(org_name), '[^a-zA-Z0-9]+', '-', 'g'))
  );
  final_slug := trim(both '-' from slug_base);

  WHILE EXISTS (SELECT 1 FROM public.organizations WHERE slug = final_slug) LOOP
    final_slug := final_slug || '-' || substr(gen_random_uuid()::text, 1, 8);
  END LOOP;

  INSERT INTO public.organizations (name, slug, plan)
  VALUES (trim(org_name), final_slug, 'basic')
  RETURNING id INTO new_org_id;

  INSERT INTO public.organization_members (user_id, organization_id, role)
  VALUES (current_user_id, new_org_id, 'admin');

  INSERT INTO public.subscriptions (organization_id, plan, plan_key)
  VALUES (new_org_id, 'basic', 'basic');

  RETURN new_org_id;
END;
$$;
-- ---------------------------------------------------------------------------
-- 12. Platform admin RPCs
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.admin_update_subscription(UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN);
CREATE OR REPLACE FUNCTION public.admin_add_org_member(
  p_organization_id UUID,
  p_user_id UUID,
  p_role TEXT DEFAULT 'member'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  member_id UUID;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_role NOT IN ('admin', 'member') THEN
    RAISE EXCEPTION 'Invalid role';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
    RAISE EXCEPTION 'Organization not found';
  END IF;

  IF NOT public.org_can_add_member(p_organization_id, p_role) THEN
    RAISE EXCEPTION 'Seat limit reached for role %', p_role;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.organization_members
    WHERE user_id = p_user_id
      AND organization_id <> p_organization_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'User already belongs to another organization';
  END IF;

  INSERT INTO public.organization_members (user_id, organization_id, role)
  VALUES (p_user_id, p_organization_id, p_role)
  ON CONFLICT (user_id, organization_id) DO UPDATE
    SET role = EXCLUDED.role, status = 'active', updated_at = now()
  RETURNING id INTO member_id;

  RETURN member_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.admin_update_subscription(
  p_organization_id UUID,
  p_plan TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_current_period_start TIMESTAMPTZ DEFAULT NULL,
  p_current_period_end TIMESTAMPTZ DEFAULT NULL,
  p_cancel_at_period_end BOOLEAN DEFAULT NULL,
  p_override_max_people INT DEFAULT NULL,
  p_override_max_attendance_sessions INT DEFAULT NULL,
  p_override_max_admin_seats INT DEFAULT NULL,
  p_override_max_member_seats INT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan_key TEXT;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  v_plan_key := CASE
    WHEN p_plan IS NULL THEN NULL
    WHEN lower(p_plan) = 'pro' THEN 'pro'
    ELSE 'basic'
  END;

  IF p_plan IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.subscription_plans WHERE key = v_plan_key
  ) THEN
    RAISE EXCEPTION 'Invalid plan';
  END IF;

  UPDATE public.subscriptions
  SET
    plan = COALESCE(v_plan_key, plan),
    plan_key = COALESCE(v_plan_key, plan_key),
    status = COALESCE(p_status, status),
    current_period_start = COALESCE(p_current_period_start, current_period_start),
    current_period_end = COALESCE(p_current_period_end, current_period_end),
    cancel_at_period_end = COALESCE(p_cancel_at_period_end, cancel_at_period_end),
    override_max_people = COALESCE(p_override_max_people, override_max_people),
    override_max_attendance_sessions = COALESCE(p_override_max_attendance_sessions, override_max_attendance_sessions),
    override_max_admin_seats = COALESCE(p_override_max_admin_seats, override_max_admin_seats),
    override_max_member_seats = COALESCE(p_override_max_member_seats, override_max_member_seats),
    updated_at = now()
  WHERE organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Subscription not found';
  END IF;

  IF v_plan_key IS NOT NULL THEN
    UPDATE public.organizations
    SET plan = v_plan_key, updated_at = now()
    WHERE id = p_organization_id;
  END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.admin_set_module_overrides(
  p_organization_id UUID,
  p_overrides JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.subscriptions
  SET
    module_overrides = public.merge_module_config(module_overrides, COALESCE(p_overrides, '{}'::jsonb)),
    updated_at = now()
  WHERE organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Subscription not found';
  END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.admin_set_subscription_features(
  p_organization_id UUID,
  p_features JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.subscriptions
  SET
    features_override = public.merge_jsonb_objects(features_override, COALESCE(p_features, '{}'::jsonb)),
    updated_at = now()
  WHERE organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Subscription not found';
  END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.admin_create_organization(
  org_name TEXT,
  org_slug TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  new_org_id UUID;
  slug_base TEXT;
  final_slug TEXT;
BEGIN
  IF NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF trim(org_name) = '' THEN
    RAISE EXCEPTION 'Organization name is required';
  END IF;

  slug_base := COALESCE(
    NULLIF(trim(org_slug), ''),
    lower(regexp_replace(trim(org_name), '[^a-zA-Z0-9]+', '-', 'g'))
  );
  final_slug := trim(both '-' from slug_base);

  WHILE EXISTS (SELECT 1 FROM public.organizations WHERE slug = final_slug) LOOP
    final_slug := final_slug || '-' || substr(gen_random_uuid()::text, 1, 8);
  END LOOP;

  INSERT INTO public.organizations (name, slug, plan)
  VALUES (trim(org_name), final_slug, 'basic')
  RETURNING id INTO new_org_id;

  INSERT INTO public.subscriptions (organization_id, plan, plan_key)
  VALUES (new_org_id, 'basic', 'basic');

  RETURN new_org_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_set_module_overrides(UUID, JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_subscription_features(UUID, JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_update_subscription(UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, INT, INT, INT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_module_overrides(UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_subscription_features(UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_subscription(UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, INT, INT, INT, INT) TO authenticated;
