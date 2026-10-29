-- Register Weddings and Child Dedication as Pro-only items in the existing
-- people_membership module group (same tier as Water Baptism/Properties/Financial).

UPDATE public.subscription_plans
SET modules = jsonb_set(
  jsonb_set(modules, '{items,weddings}', '{"enabled": false}'::jsonb, true),
  '{items,dedications}',
  '{"enabled": false}'::jsonb,
  true
)
WHERE key = 'basic';
UPDATE public.subscription_plans
SET modules = jsonb_set(
  jsonb_set(modules, '{items,weddings}', '{"enabled": true}'::jsonb, true),
  '{items,dedications}',
  '{"enabled": true}'::jsonb,
  true
)
WHERE key = 'pro';
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
    WHEN 'weddings' THEN 'people_membership'
    WHEN 'dedications' THEN 'people_membership'
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
