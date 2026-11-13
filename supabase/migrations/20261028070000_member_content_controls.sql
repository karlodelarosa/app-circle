CREATE POLICY "Prayer authors delete own requests"
ON public.circle_prayer_requests FOR DELETE TO authenticated
USING (
  person_id=public.circle_current_person_id(organization_id)
  OR public.circle_is_org_admin(organization_id)
  OR (scope='circle' AND public.circle_can_lead_group(cell_group_id))
);

CREATE POLICY "Members edit own testimony drafts"
ON public.circle_testimonies FOR UPDATE TO authenticated
USING (
  status='draft' AND published_at IS NULL AND created_by=auth.uid()
  AND author_person_id=public.circle_current_person_id(organization_id)
)
WITH CHECK (
  status='draft' AND published_at IS NULL AND created_by=auth.uid()
  AND author_person_id=public.circle_current_person_id(organization_id)
  AND cell_group_id IS NOT NULL AND public.circle_can_access_group(cell_group_id)
);

CREATE POLICY "Members withdraw own testimony drafts"
ON public.circle_testimonies FOR DELETE TO authenticated
USING (
  status='draft' AND published_at IS NULL AND created_by=auth.uid()
  AND author_person_id=public.circle_current_person_id(organization_id)
);

CREATE POLICY "Members cancel own gathering RSVP"
ON public.circle_gathering_rsvps FOR DELETE TO authenticated
USING (
  person_id=public.circle_current_person_id(organization_id)
  AND EXISTS (
    SELECT 1 FROM public.circle_gatherings gathering
    WHERE gathering.id=gathering_id
      AND gathering.organization_id=circle_gathering_rsvps.organization_id
      AND gathering.starts_at>now()
  )
);

CREATE OR REPLACE FUNCTION public.withdraw_circle_guest_consent(p_connection_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE connection public.circle_guest_connections%ROWTYPE;
BEGIN
  SELECT * INTO connection FROM public.circle_guest_connections WHERE id=p_connection_id;
  IF connection.id IS NULL OR NOT (public.circle_is_org_admin(connection.organization_id) OR public.circle_can_lead_group(connection.cell_group_id)) THEN
    RAISE EXCEPTION 'Guest record unavailable';
  END IF;
  UPDATE public.circle_guest_connections
  SET follow_up_opt_in=false,consented_at=NULL,status='closed',updated_at=now()
  WHERE id=connection.id;
  INSERT INTO public.circle_security_audit_events(
    organization_id,actor_user_id,action,target_type,target_id,result,request_id
  ) VALUES(
    connection.organization_id,auth.uid(),'privacy.consent_withdrawn','guest_connection',connection.id::text,
    'success','database-'||gen_random_uuid()::text
  );
END;
$$;

REVOKE ALL ON FUNCTION public.withdraw_circle_guest_consent(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.withdraw_circle_guest_consent(UUID) TO authenticated;
