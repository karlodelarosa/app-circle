-- Fix audit log RLS: replace revoked is_org_member() with inline membership check.

DROP POLICY IF EXISTS "Org members can view audit logs when feature enabled" ON public.organization_audit_logs;
CREATE POLICY "Org members can view audit logs when feature enabled"
  ON public.organization_audit_logs FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.organization_id = organization_audit_logs.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_feature(organization_id, 'audit_trail')
  );
