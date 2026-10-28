CREATE TABLE IF NOT EXISTS public.circle_security_audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
  actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL CHECK (char_length(action) BETWEEN 1 AND 100),
  target_type TEXT NOT NULL CHECK (char_length(target_type) BETWEEN 1 AND 80),
  target_id TEXT CHECK (target_id IS NULL OR char_length(target_id) <= 160),
  result TEXT NOT NULL CHECK (result IN ('success','denied','failed')),
  request_id TEXT NOT NULL CHECK (char_length(request_id) BETWEEN 1 AND 128),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS circle_security_audit_events_tenant_time_idx
  ON public.circle_security_audit_events(organization_id,created_at DESC);
ALTER TABLE public.circle_security_audit_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Administrators read tenant security events"
ON public.circle_security_audit_events FOR SELECT TO authenticated
USING (organization_id IS NOT NULL AND public.circle_is_org_admin(organization_id));

CREATE OR REPLACE FUNCTION public.circle_security_events_are_append_only()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  RAISE EXCEPTION 'Security audit events are append-only';
END;
$$;

CREATE TRIGGER circle_security_audit_events_append_only
BEFORE UPDATE OR DELETE ON public.circle_security_audit_events
FOR EACH ROW EXECUTE FUNCTION public.circle_security_events_are_append_only();

REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON public.circle_security_audit_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.circle_security_audit_events TO authenticated;
GRANT INSERT ON public.circle_security_audit_events TO service_role;
