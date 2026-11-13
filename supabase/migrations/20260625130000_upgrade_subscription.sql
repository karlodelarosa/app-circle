-- Plan tier ordering and org-admin subscription upgrades

ALTER TABLE public.subscription_plans
  ADD COLUMN IF NOT EXISTS sort_order INT NOT NULL DEFAULT 0;
UPDATE public.subscription_plans SET sort_order = 1 WHERE key = 'basic';
UPDATE public.subscription_plans SET sort_order = 2 WHERE key = 'pro';
CREATE OR REPLACE FUNCTION public.upgrade_organization_subscription(
  p_organization_id UUID,
  p_plan_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_current_plan_key TEXT;
  v_current_tier INT;
  v_target_tier INT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.is_org_admin(p_organization_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT plan_key
  INTO v_current_plan_key
  FROM public.subscriptions
  WHERE organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Subscription not found';
  END IF;

  SELECT sort_order
  INTO v_target_tier
  FROM public.subscription_plans
  WHERE key = p_plan_key
    AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid plan';
  END IF;

  SELECT sort_order
  INTO v_current_tier
  FROM public.subscription_plans
  WHERE key = v_current_plan_key;

  IF v_current_tier IS NULL THEN
    v_current_tier := 0;
  END IF;

  IF v_target_tier <= v_current_tier THEN
    RAISE EXCEPTION 'Can only upgrade to a higher tier plan';
  END IF;

  UPDATE public.subscriptions
  SET
    plan_key = p_plan_key,
    plan = p_plan_key,
    status = 'active',
    cancel_at_period_end = false,
    updated_at = now()
  WHERE organization_id = p_organization_id;

  UPDATE public.organizations
  SET plan = p_plan_key, updated_at = now()
  WHERE id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION public.upgrade_organization_subscription(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upgrade_organization_subscription(UUID, TEXT) TO authenticated;
