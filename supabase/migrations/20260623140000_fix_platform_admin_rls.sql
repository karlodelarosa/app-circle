-- is_platform_admin() has EXECUTE revoked from authenticated (project convention),
-- but platform-admin RLS policies called it — blocking reads for seeded admins.
-- Replace with inline membership checks (same pattern as fix_rls_policies.sql).

DROP POLICY IF EXISTS "Platform admins can view platform_admins" ON public.platform_admins;
DROP POLICY IF EXISTS "Platform admins can view all organizations" ON public.organizations;
DROP POLICY IF EXISTS "Platform admins can insert organizations" ON public.organizations;
DROP POLICY IF EXISTS "Platform admins can update all organizations" ON public.organizations;
DROP POLICY IF EXISTS "Platform admins can view all org members" ON public.organization_members;
DROP POLICY IF EXISTS "Platform admins can insert org members" ON public.organization_members;
DROP POLICY IF EXISTS "Platform admins can update org members" ON public.organization_members;
DROP POLICY IF EXISTS "Platform admins can view all subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Platform admins can insert subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Platform admins can update all subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Platform admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own platform admin row" ON public.platform_admins;
CREATE POLICY "Users can view own platform admin row"
  ON public.platform_admins FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY "Platform admins can view all organizations"
  ON public.organizations FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  );
CREATE POLICY "Platform admins can insert organizations"
  ON public.organizations FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  );
CREATE POLICY "Platform admins can update all organizations"
  ON public.organizations FOR UPDATE
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
CREATE POLICY "Platform admins can view all org members"
  ON public.organization_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  );
CREATE POLICY "Platform admins can insert org members"
  ON public.organization_members FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  );
CREATE POLICY "Platform admins can update org members"
  ON public.organization_members FOR UPDATE
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
CREATE POLICY "Platform admins can view all subscriptions"
  ON public.subscriptions FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  );
CREATE POLICY "Platform admins can insert subscriptions"
  ON public.subscriptions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  );
CREATE POLICY "Platform admins can update all subscriptions"
  ON public.subscriptions FOR UPDATE
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
CREATE POLICY "Platform admins can view all profiles"
  ON public.profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
    )
  );
