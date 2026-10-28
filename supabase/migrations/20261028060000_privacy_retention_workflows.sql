CREATE TABLE IF NOT EXISTS public.circle_organization_settings (
  organization_id UUID PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
  timezone TEXT NOT NULL DEFAULT 'UTC' CHECK (char_length(timezone) BETWEEN 1 AND 80),
  guest_rsvp_retention_days INTEGER NOT NULL DEFAULT 365 CHECK (guest_rsvp_retention_days BETWEEN 30 AND 3650),
  connection_retention_days INTEGER NOT NULL DEFAULT 730 CHECK (connection_retention_days BETWEEN 30 AND 3650),
  signup_retention_days INTEGER NOT NULL DEFAULT 730 CHECK (signup_retention_days BETWEEN 30 AND 3650),
  prayer_retention_days INTEGER NOT NULL DEFAULT 730 CHECK (prayer_retention_days BETWEEN 30 AND 3650),
  notification_channels JSONB NOT NULL DEFAULT '{"email":false,"sms":false}'::jsonb,
  public_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  abuse_protection JSONB NOT NULL DEFAULT '{"publicSubmissionsPer15Minutes":10}'::jsonb,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.circle_organization_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Administrators manage Circles organization settings"
ON public.circle_organization_settings FOR ALL TO authenticated
USING (public.circle_is_org_admin(organization_id))
WITH CHECK (public.circle_is_org_admin(organization_id));
GRANT SELECT,INSERT,UPDATE ON public.circle_organization_settings TO authenticated;

CREATE OR REPLACE VIEW public.circle_public_organization_settings
WITH (security_invoker=false)
AS SELECT organization_id,timezone,public_metadata
FROM public.circle_organization_settings;
REVOKE ALL ON public.circle_public_organization_settings FROM PUBLIC;
GRANT SELECT ON public.circle_public_organization_settings TO anon,authenticated;

CREATE TABLE IF NOT EXISTS public.circle_privacy_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  request_type TEXT NOT NULL CHECK (request_type IN ('access','export','correction','deletion','withdraw_consent')),
  subject_type TEXT NOT NULL CHECK (subject_type IN ('person','guest_connection','account')),
  subject_id UUID NOT NULL,
  notes TEXT NOT NULL DEFAULT '' CHECK (char_length(notes) <= 2000),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','completed','rejected')),
  requested_by UUID NOT NULL REFERENCES auth.users(id),
  resolved_by UUID REFERENCES auth.users(id),
  resolved_at TIMESTAMPTZ,
  resolution_notes TEXT NOT NULL DEFAULT '' CHECK (char_length(resolution_notes) <= 2000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.circle_privacy_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Administrators manage tenant privacy requests"
ON public.circle_privacy_requests FOR ALL TO authenticated
USING (public.circle_is_org_admin(organization_id))
WITH CHECK (public.circle_is_org_admin(organization_id));
GRANT SELECT,INSERT,UPDATE ON public.circle_privacy_requests TO authenticated;

CREATE OR REPLACE FUNCTION public.export_circle_person_data(p_organization_id UUID,p_person_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT public.circle_is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.people WHERE id=p_person_id AND organization_id=p_organization_id) THEN
    RAISE EXCEPTION 'Person is unavailable';
  END IF;
  RETURN jsonb_build_object(
    'exportedAt',now(),
    'person',(SELECT to_jsonb(person) FROM public.people person WHERE person.id=p_person_id),
    'memberships',COALESCE((SELECT jsonb_agg(to_jsonb(member)) FROM public.cell_group_members member
      JOIN public.cell_groups group_row ON group_row.id=member.cell_group_id
      WHERE member.person_id=p_person_id AND group_row.organization_id=p_organization_id),'[]'::jsonb),
    'rsvps',COALESCE((SELECT jsonb_agg(to_jsonb(rsvp)) FROM public.circle_gathering_rsvps rsvp
      WHERE rsvp.organization_id=p_organization_id AND rsvp.person_id=p_person_id),'[]'::jsonb),
    'prayers',COALESCE((SELECT jsonb_agg(to_jsonb(prayer)) FROM public.circle_prayer_requests prayer
      WHERE prayer.organization_id=p_organization_id AND prayer.person_id=p_person_id),'[]'::jsonb),
    'signups',COALESCE((SELECT jsonb_agg(to_jsonb(signup)) FROM public.circle_group_signups signup
      WHERE signup.organization_id=p_organization_id AND signup.person_id=p_person_id),'[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_circle_guest_data(p_connection_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE connection public.circle_guest_connections%ROWTYPE;
BEGIN
  SELECT * INTO connection FROM public.circle_guest_connections WHERE id=p_connection_id;
  IF connection.id IS NULL OR NOT (public.circle_is_org_admin(connection.organization_id) OR public.circle_can_lead_group(connection.cell_group_id)) THEN
    RAISE EXCEPTION 'Guest record unavailable';
  END IF;
  DELETE FROM public.circle_join_interests WHERE connection_id=connection.id;
  DELETE FROM public.circle_guest_rsvps WHERE connection_id=connection.id;
  DELETE FROM public.circle_guest_connections WHERE id=connection.id;
  INSERT INTO public.circle_security_audit_events(
    organization_id,actor_user_id,action,target_type,target_id,result,request_id
  ) VALUES(
    connection.organization_id,auth.uid(),'privacy.guest_deleted','guest_connection',connection.id::text,
    'success','database-'||gen_random_uuid()::text
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_circle_pii_retention(p_organization_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE settings public.circle_organization_settings%ROWTYPE; rsvp_count INTEGER; connection_count INTEGER;
  signup_count INTEGER; prayer_count INTEGER;
BEGIN
  IF auth.role()<>'service_role' AND NOT public.circle_is_org_admin(p_organization_id) THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  SELECT * INTO settings FROM public.circle_organization_settings WHERE organization_id=p_organization_id;
  IF settings.organization_id IS NULL THEN
    INSERT INTO public.circle_organization_settings(organization_id) VALUES(p_organization_id)
    RETURNING * INTO settings;
  END IF;
  DELETE FROM public.circle_guest_rsvps
    WHERE organization_id=p_organization_id AND updated_at < now()-(settings.guest_rsvp_retention_days||' days')::interval;
  GET DIAGNOSTICS rsvp_count=ROW_COUNT;
  DELETE FROM public.circle_join_interests
    WHERE organization_id=p_organization_id AND updated_at < now()-(settings.connection_retention_days||' days')::interval;
  DELETE FROM public.circle_guest_connections
    WHERE organization_id=p_organization_id AND updated_at < now()-(settings.connection_retention_days||' days')::interval;
  GET DIAGNOSTICS connection_count=ROW_COUNT;
  DELETE FROM public.circle_group_signups
    WHERE organization_id=p_organization_id AND updated_at < now()-(settings.signup_retention_days||' days')::interval;
  GET DIAGNOSTICS signup_count=ROW_COUNT;
  DELETE FROM public.circle_prayer_requests
    WHERE organization_id=p_organization_id AND created_at < now()-(settings.prayer_retention_days||' days')::interval;
  GET DIAGNOSTICS prayer_count=ROW_COUNT;
  INSERT INTO public.circle_security_audit_events(
    organization_id,actor_user_id,action,target_type,target_id,result,request_id,metadata
  ) VALUES(
    p_organization_id,auth.uid(),'privacy.retention_applied','organization',p_organization_id::text,
    'success','database-'||gen_random_uuid()::text,
    jsonb_build_object('guestRsvps',rsvp_count,'connections',connection_count,'signups',signup_count,'prayers',prayer_count)
  );
  RETURN jsonb_build_object('guestRsvps',rsvp_count,'connections',connection_count,'signups',signup_count,'prayers',prayer_count);
END;
$$;

REVOKE ALL ON FUNCTION public.export_circle_person_data(UUID,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.delete_circle_guest_data(UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.apply_circle_pii_retention(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.export_circle_person_data(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_circle_guest_data(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_circle_pii_retention(UUID) TO authenticated,service_role;
