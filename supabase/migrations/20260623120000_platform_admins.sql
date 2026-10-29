-- Platform admins for Ministry Lens SaaS console (cross-tenant management)

CREATE TABLE public.platform_admins (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_admins
    WHERE user_id = auth.uid()
  );
$$;
CREATE POLICY "Platform admins can view platform_admins"
  ON public.platform_admins FOR SELECT
  USING (public.is_platform_admin());
-- Organizations: platform admin access
CREATE POLICY "Platform admins can view all organizations"
  ON public.organizations FOR SELECT
  USING (public.is_platform_admin());
CREATE POLICY "Platform admins can insert organizations"
  ON public.organizations FOR INSERT
  WITH CHECK (public.is_platform_admin());
CREATE POLICY "Platform admins can update all organizations"
  ON public.organizations FOR UPDATE
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());
-- Organization members: platform admin access
CREATE POLICY "Platform admins can view all org members"
  ON public.organization_members FOR SELECT
  USING (public.is_platform_admin());
CREATE POLICY "Platform admins can insert org members"
  ON public.organization_members FOR INSERT
  WITH CHECK (public.is_platform_admin());
CREATE POLICY "Platform admins can update org members"
  ON public.organization_members FOR UPDATE
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());
-- Subscriptions: platform admin access
CREATE POLICY "Platform admins can view all subscriptions"
  ON public.subscriptions FOR SELECT
  USING (public.is_platform_admin());
CREATE POLICY "Platform admins can insert subscriptions"
  ON public.subscriptions FOR INSERT
  WITH CHECK (public.is_platform_admin());
CREATE POLICY "Platform admins can update all subscriptions"
  ON public.subscriptions FOR UPDATE
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());
-- Profiles: platform admin read for member display
CREATE POLICY "Platform admins can view all profiles"
  ON public.profiles FOR SELECT
  USING (public.is_platform_admin());
-- Admin RPC: create organization without self-serve constraints
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

  INSERT INTO public.organizations (name, slug)
  VALUES (trim(org_name), final_slug)
  RETURNING id INTO new_org_id;

  INSERT INTO public.subscriptions (organization_id)
  VALUES (new_org_id);

  RETURN new_org_id;
END;
$$;
-- Admin RPC: add member to organization
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

  IF EXISTS (
    SELECT 1 FROM public.organization_members
    WHERE user_id = p_user_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'User already belongs to an organization';
  END IF;

  INSERT INTO public.organization_members (user_id, organization_id, role)
  VALUES (p_user_id, p_organization_id, p_role)
  ON CONFLICT (user_id, organization_id) DO UPDATE
    SET role = EXCLUDED.role, status = 'active', updated_at = now()
  RETURNING id INTO member_id;

  RETURN member_id;
END;
$$;
-- Admin RPC: update subscription
CREATE OR REPLACE FUNCTION public.admin_update_subscription(
  p_organization_id UUID,
  p_plan TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_current_period_start TIMESTAMPTZ DEFAULT NULL,
  p_current_period_end TIMESTAMPTZ DEFAULT NULL,
  p_cancel_at_period_end BOOLEAN DEFAULT NULL
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
    plan = COALESCE(p_plan, plan),
    status = COALESCE(p_status, status),
    current_period_start = COALESCE(p_current_period_start, current_period_start),
    current_period_end = COALESCE(p_current_period_end, current_period_end),
    cancel_at_period_end = COALESCE(p_cancel_at_period_end, cancel_at_period_end),
    updated_at = now()
  WHERE organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Subscription not found';
  END IF;

  IF p_plan IS NOT NULL THEN
    UPDATE public.organizations
    SET plan = p_plan, updated_at = now()
    WHERE id = p_organization_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_create_organization(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_org_member(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_subscription(UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN) TO authenticated;
