BEGIN;

-- Staging a walk-in prepares the attendance roster. The guest becomes
-- "visited" only when the leader saves attendance for the gathering.
CREATE OR REPLACE FUNCTION public.stage_circle_walk_in(
  p_gathering_id UUID,p_name TEXT,p_email TEXT,p_phone TEXT,p_preferred_contact TEXT,p_consent BOOLEAN
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE g public.circle_gatherings%ROWTYPE; cid UUID; rid UUID; contact_key TEXT;
BEGIN
  SELECT * INTO g FROM public.circle_gatherings WHERE id=p_gathering_id;
  IF g.id IS NULL OR NOT public.circle_can_lead_group(g.cell_group_id) THEN RAISE EXCEPTION 'Leader access required'; END IF;
  IF nullif(trim(p_name),'') IS NULL THEN RAISE EXCEPTION 'Guest name is required'; END IF;
  contact_key:=public.circle_normalize_guest_contact(p_email,p_phone,'');
  IF contact_key='contact:' THEN RAISE EXCEPTION 'Email or phone is required'; END IF;
  IF p_preferred_contact NOT IN ('email','phone','either') THEN RAISE EXCEPTION 'A valid contact preference is required'; END IF;
  IF p_preferred_contact='email' AND nullif(trim(p_email),'') IS NULL THEN RAISE EXCEPTION 'Email is required for email follow-up'; END IF;
  IF p_preferred_contact='phone' AND nullif(trim(p_phone),'') IS NULL THEN RAISE EXCEPTION 'Phone is required for phone follow-up'; END IF;
  cid:=public.circle_upsert_guest_connection(g.organization_id,g.cell_group_id,p_name,p_email,p_phone,'',p_preferred_contact,p_consent,CASE WHEN p_consent THEN now() ELSE NULL END);
  INSERT INTO public.circle_guest_rsvps(organization_id,gathering_id,guest_name,email,phone,normalized_contact,status,connection_id)
  VALUES(g.organization_id,g.id,trim(p_name),lower(trim(p_email)),trim(p_phone),contact_key,'attending',cid)
  ON CONFLICT(gathering_id,normalized_contact) DO UPDATE SET guest_name=excluded.guest_name,email=excluded.email,phone=excluded.phone,status='attending',connection_id=excluded.connection_id,updated_at=now()
  RETURNING id INTO rid;
  RETURN jsonb_build_object('ok',true,'guestRsvpId',rid,'connectionId',cid);
END;
$$;

COMMIT;
