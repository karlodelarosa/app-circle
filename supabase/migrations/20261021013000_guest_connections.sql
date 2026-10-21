-- Guest Connections: a staged, Circle-scoped follow-up workflow.
-- Additive and compatible with existing RSVP, interest, and visitor records.

BEGIN;

CREATE TABLE IF NOT EXISTS public.circle_guest_connections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID NOT NULL REFERENCES public.cell_groups(id) ON DELETE CASCADE,
  normalized_contact TEXT NOT NULL,
  guest_name TEXT NOT NULL CHECK (char_length(guest_name) BETWEEN 1 AND 120),
  email TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  preferred_contact TEXT NOT NULL DEFAULT 'either' CHECK (preferred_contact IN ('email','phone','either')),
  follow_up_opt_in BOOLEAN NOT NULL DEFAULT false,
  consented_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','contacted','visited','connected','closed')),
  claimed_by_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  converted_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  last_activity_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, cell_group_id, normalized_contact)
);

CREATE TABLE IF NOT EXISTS public.circle_guest_connection_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  connection_id UUID NOT NULL REFERENCES public.circle_guest_connections(id) ON DELETE CASCADE,
  activity_type TEXT NOT NULL CHECK (activity_type IN ('note','contacted','claimed','unclaimed','status_changed','converted')),
  body TEXT NOT NULL DEFAULT '' CHECK (char_length(body) <= 2000),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.circle_guest_rsvps
  ADD COLUMN IF NOT EXISTS connection_id UUID REFERENCES public.circle_guest_connections(id) ON DELETE SET NULL;
ALTER TABLE public.circle_join_interests
  ADD COLUMN IF NOT EXISTS connection_id UUID REFERENCES public.circle_guest_connections(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS circle_guest_connections_queue_idx
  ON public.circle_guest_connections(organization_id, cell_group_id, status, last_activity_at DESC);
CREATE INDEX IF NOT EXISTS circle_guest_connections_attention_idx
  ON public.circle_guest_connections(organization_id, last_activity_at DESC)
  WHERE follow_up_opt_in AND status='new';
CREATE INDEX IF NOT EXISTS circle_guest_connection_activities_idx
  ON public.circle_guest_connection_activities(connection_id, created_at DESC);
CREATE INDEX IF NOT EXISTS circle_guest_rsvps_connection_idx
  ON public.circle_guest_rsvps(connection_id);
CREATE INDEX IF NOT EXISTS circle_join_interests_connection_idx
  ON public.circle_join_interests(connection_id);

CREATE OR REPLACE FUNCTION public.circle_normalize_guest_contact(p_email TEXT, p_phone TEXT, p_fallback TEXT DEFAULT '')
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path='' AS $$
  SELECT CASE
    WHEN nullif(lower(trim(COALESCE(p_email,''))), '') IS NOT NULL
      THEN 'email:' || lower(trim(p_email))
    WHEN nullif(regexp_replace(COALESCE(p_phone,''), '[^0-9+]', '', 'g'), '') IS NOT NULL
      THEN 'phone:' || regexp_replace(p_phone, '[^0-9+]', '', 'g')
    ELSE 'contact:' || lower(trim(COALESCE(p_fallback,'')))
  END;
$$;

CREATE OR REPLACE FUNCTION public.circle_upsert_guest_connection(
  p_organization_id UUID,
  p_cell_group_id UUID,
  p_name TEXT,
  p_email TEXT,
  p_phone TEXT,
  p_fallback_contact TEXT,
  p_preferred_contact TEXT,
  p_opt_in BOOLEAN,
  p_consented_at TIMESTAMPTZ DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE contact_key TEXT; connection_id UUID;
BEGIN
  contact_key := public.circle_normalize_guest_contact(p_email,p_phone,p_fallback_contact);
  IF contact_key='contact:' THEN RAISE EXCEPTION 'Email or phone is required'; END IF;
  INSERT INTO public.circle_guest_connections(
    organization_id,cell_group_id,normalized_contact,guest_name,email,phone,
    preferred_contact,follow_up_opt_in,consented_at,last_activity_at
  ) VALUES(
    p_organization_id,p_cell_group_id,contact_key,trim(p_name),lower(trim(COALESCE(p_email,''))),trim(COALESCE(p_phone,'')),
    CASE WHEN p_preferred_contact IN ('email','phone','either') THEN p_preferred_contact ELSE 'either' END,
    COALESCE(p_opt_in,false),CASE WHEN p_opt_in THEN COALESCE(p_consented_at,now()) ELSE NULL END,now()
  )
  ON CONFLICT(organization_id,cell_group_id,normalized_contact) DO UPDATE SET
    guest_name=excluded.guest_name,
    email=CASE WHEN excluded.email<>'' THEN excluded.email ELSE circle_guest_connections.email END,
    phone=CASE WHEN excluded.phone<>'' THEN excluded.phone ELSE circle_guest_connections.phone END,
    preferred_contact=CASE WHEN excluded.follow_up_opt_in THEN excluded.preferred_contact ELSE circle_guest_connections.preferred_contact END,
    follow_up_opt_in=circle_guest_connections.follow_up_opt_in OR excluded.follow_up_opt_in,
    consented_at=COALESCE(circle_guest_connections.consented_at,excluded.consented_at),
    status=CASE WHEN circle_guest_connections.status='closed' AND excluded.follow_up_opt_in THEN 'new' ELSE circle_guest_connections.status END,
    last_activity_at=now(),updated_at=now()
  RETURNING id INTO connection_id;
  RETURN connection_id;
END;
$$;

-- Backfill RSVP-only connections without granting follow-up consent.
INSERT INTO public.circle_guest_connections(
  organization_id,cell_group_id,normalized_contact,guest_name,email,phone,
  follow_up_opt_in,status,converted_person_id,last_activity_at,created_at,updated_at
)
SELECT r.organization_id,g.cell_group_id,r.normalized_contact,r.guest_name,r.email,r.phone,
       false,CASE WHEN r.converted_person_id IS NOT NULL THEN 'connected' ELSE 'new' END,
       r.converted_person_id,r.updated_at,r.created_at,r.updated_at
FROM public.circle_guest_rsvps r
JOIN public.circle_gatherings g ON g.id=r.gathering_id
ON CONFLICT(organization_id,cell_group_id,normalized_contact) DO UPDATE SET
  converted_person_id=COALESCE(circle_guest_connections.converted_person_id,excluded.converted_person_id),
  status=CASE WHEN COALESCE(circle_guest_connections.converted_person_id,excluded.converted_person_id) IS NOT NULL THEN 'connected' ELSE circle_guest_connections.status END,
  last_activity_at=GREATEST(circle_guest_connections.last_activity_at,excluded.last_activity_at);

UPDATE public.circle_guest_rsvps r SET connection_id=c.id
FROM public.circle_gatherings g, public.circle_guest_connections c
WHERE r.gathering_id=g.id AND c.organization_id=r.organization_id
  AND c.cell_group_id=g.cell_group_id AND c.normalized_contact=r.normalized_contact
  AND r.connection_id IS NULL;

-- Existing joining-interest submissions are explicit follow-up requests.
INSERT INTO public.circle_guest_connections(
  organization_id,cell_group_id,normalized_contact,guest_name,email,phone,
  preferred_contact,follow_up_opt_in,consented_at,status,last_activity_at,created_at,updated_at
)
SELECT i.organization_id,l.cell_group_id,
       public.circle_normalize_guest_contact(CASE WHEN i.contact LIKE '%@%' THEN i.contact ELSE '' END,CASE WHEN i.contact NOT LIKE '%@%' THEN i.contact ELSE '' END,i.contact),
       i.name,CASE WHEN i.contact LIKE '%@%' THEN lower(trim(i.contact)) ELSE '' END,
       CASE WHEN i.contact NOT LIKE '%@%' THEN trim(i.contact) ELSE '' END,
       CASE WHEN i.contact LIKE '%@%' THEN 'email' ELSE 'phone' END,true,i.created_at,
       CASE WHEN i.status='contacted' THEN 'contacted' WHEN i.status='closed' THEN 'closed' ELSE 'new' END,
       i.updated_at,i.created_at,i.updated_at
FROM public.circle_join_interests i
JOIN public.circle_public_listings l ON l.id=i.listing_id
ON CONFLICT(organization_id,cell_group_id,normalized_contact) DO UPDATE SET
  follow_up_opt_in=true,
  consented_at=COALESCE(circle_guest_connections.consented_at,excluded.consented_at),
  status=CASE
    WHEN circle_guest_connections.status='connected' THEN 'connected'
    WHEN excluded.status='contacted' THEN 'contacted'
    WHEN circle_guest_connections.follow_up_opt_in THEN circle_guest_connections.status
    ELSE excluded.status
  END,
  last_activity_at=GREATEST(circle_guest_connections.last_activity_at,excluded.last_activity_at),updated_at=now();

UPDATE public.circle_join_interests i SET connection_id=c.id
FROM public.circle_public_listings l, public.circle_guest_connections c
WHERE i.listing_id=l.id AND c.organization_id=i.organization_id AND c.cell_group_id=l.cell_group_id
  AND c.normalized_contact=public.circle_normalize_guest_contact(CASE WHEN i.contact LIKE '%@%' THEN i.contact ELSE '' END,CASE WHEN i.contact NOT LIKE '%@%' THEN i.contact ELSE '' END,i.contact)
  AND i.connection_id IS NULL;

ALTER TABLE public.circle_guest_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_guest_connection_activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Leaders read guest connections" ON public.circle_guest_connections FOR SELECT TO authenticated
  USING(public.circle_is_org_admin(organization_id) OR public.circle_can_lead_group(cell_group_id));
CREATE POLICY "Leaders read guest connection activities" ON public.circle_guest_connection_activities FOR SELECT TO authenticated
  USING(EXISTS(SELECT 1 FROM public.circle_guest_connections c WHERE c.id=connection_id AND (public.circle_is_org_admin(c.organization_id) OR public.circle_can_lead_group(c.cell_group_id))));

CREATE OR REPLACE FUNCTION public.submit_circle_guest_rsvp(p_gathering_id UUID,p_name TEXT,p_email TEXT,p_phone TEXT,p_status TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE g public.circle_gatherings%ROWTYPE; contact TEXT; rid UUID; cid UUID;
BEGIN
  SELECT * INTO g FROM public.circle_gatherings WHERE id=p_gathering_id AND visibility='public' AND published_at IS NOT NULL AND guest_rsvp_enabled AND status='scheduled'
    AND EXISTS(SELECT 1 FROM public.circle_public_spaces s WHERE s.organization_id=circle_gatherings.organization_id AND s.is_published);
  IF g.id IS NULL THEN RAISE EXCEPTION 'Guest RSVP is unavailable'; END IF;
  IF nullif(trim(p_name),'') IS NULL OR p_status NOT IN('attending','tentative','declined') THEN RAISE EXCEPTION 'A valid name and response are required'; END IF;
  contact:=public.circle_normalize_guest_contact(p_email,p_phone,'');
  IF contact='contact:' THEN RAISE EXCEPTION 'Email or phone is required'; END IF;
  cid:=public.circle_upsert_guest_connection(g.organization_id,g.cell_group_id,p_name,p_email,p_phone,'','either',false,NULL);
  INSERT INTO public.circle_guest_rsvps(organization_id,gathering_id,guest_name,email,phone,normalized_contact,status,connection_id)
  VALUES(g.organization_id,g.id,trim(p_name),lower(trim(p_email)),trim(p_phone),contact,p_status,cid)
  ON CONFLICT(gathering_id,normalized_contact) DO UPDATE SET guest_name=excluded.guest_name,email=excluded.email,phone=excluded.phone,status=excluded.status,connection_id=excluded.connection_id,updated_at=now()
  RETURNING id INTO rid;
  RETURN jsonb_build_object('ok',true,'id',rid,'connectionId',cid);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_circle_interest(p_listing_id UUID,p_name TEXT,p_contact TEXT,p_message TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE l public.circle_public_listings%ROWTYPE; rid UUID; cid UUID; email_value TEXT:=''; phone_value TEXT:='';
BEGIN
  SELECT * INTO l FROM public.circle_public_listings WHERE (id=p_listing_id OR cell_group_id=p_listing_id) AND is_published
    AND EXISTS(SELECT 1 FROM public.circle_public_spaces s WHERE s.organization_id=circle_public_listings.organization_id AND s.is_published) LIMIT 1;
  IF l.id IS NULL THEN RAISE EXCEPTION 'Circle listing unavailable'; END IF;
  IF nullif(trim(p_name),'') IS NULL OR char_length(trim(p_contact))<3 THEN RAISE EXCEPTION 'Name and contact are required'; END IF;
  IF p_contact LIKE '%@%' THEN email_value:=p_contact; ELSE phone_value:=p_contact; END IF;
  cid:=public.circle_upsert_guest_connection(l.organization_id,l.cell_group_id,p_name,email_value,phone_value,p_contact,CASE WHEN email_value<>'' THEN 'email' ELSE 'phone' END,true,now());
  SELECT id INTO rid FROM public.circle_join_interests WHERE listing_id=l.id AND connection_id=cid ORDER BY created_at DESC LIMIT 1;
  IF rid IS NULL THEN
    INSERT INTO public.circle_join_interests(organization_id,listing_id,name,contact,message,status,connection_id)
    VALUES(l.organization_id,l.id,trim(p_name),trim(p_contact),left(trim(p_message),1000),'new',cid) RETURNING id INTO rid;
  ELSE
    UPDATE public.circle_join_interests SET name=trim(p_name),contact=trim(p_contact),message=left(trim(p_message),1000),status='new',updated_at=now() WHERE id=rid;
  END IF;
  RETURN jsonb_build_object('ok',true,'id',rid,'connectionId',cid);
END;
$$;

CREATE OR REPLACE FUNCTION public.request_circle_connection(
  p_cell_group_id UUID,p_guest_rsvp_id UUID,p_name TEXT,p_email TEXT,p_phone TEXT,
  p_preferred_contact TEXT,p_message TEXT,p_consent BOOLEAN
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE listing public.circle_public_listings%ROWTYPE; guest public.circle_guest_rsvps%ROWTYPE; group_row public.cell_groups%ROWTYPE; cid UUID; interest_id UUID; contact_key TEXT;
BEGIN
  SELECT * INTO group_row FROM public.cell_groups WHERE id=p_cell_group_id AND status='active';
  IF group_row.id IS NULL THEN RAISE EXCEPTION 'Circle unavailable'; END IF;
  SELECT * INTO listing FROM public.circle_public_listings WHERE cell_group_id=p_cell_group_id AND is_published
    AND EXISTS(SELECT 1 FROM public.circle_public_spaces s WHERE s.organization_id=circle_public_listings.organization_id AND s.is_published);
  IF NOT COALESCE(p_consent,false) THEN RAISE EXCEPTION 'Consent is required'; END IF;
  IF nullif(trim(p_name),'') IS NULL OR p_preferred_contact NOT IN ('email','phone','either') THEN RAISE EXCEPTION 'Name and contact preference are required'; END IF;
  contact_key:=public.circle_normalize_guest_contact(p_email,p_phone,'');
  IF contact_key='contact:' THEN RAISE EXCEPTION 'Email or phone is required'; END IF;
  IF p_preferred_contact='email' AND nullif(trim(p_email),'') IS NULL THEN RAISE EXCEPTION 'Email is required for email follow-up'; END IF;
  IF p_preferred_contact='phone' AND nullif(trim(p_phone),'') IS NULL THEN RAISE EXCEPTION 'Phone is required for phone follow-up'; END IF;
  IF p_guest_rsvp_id IS NOT NULL THEN
    SELECT r.* INTO guest FROM public.circle_guest_rsvps r JOIN public.circle_gatherings g ON g.id=r.gathering_id
      WHERE r.id=p_guest_rsvp_id AND r.organization_id=group_row.organization_id AND g.cell_group_id=group_row.id
        AND g.visibility='public' AND g.published_at IS NOT NULL;
    IF guest.id IS NULL OR guest.normalized_contact<>contact_key THEN RAISE EXCEPTION 'RSVP does not match this Circle and contact'; END IF;
  ELSIF listing.id IS NULL THEN
    RAISE EXCEPTION 'Circle listing unavailable';
  END IF;
  cid:=public.circle_upsert_guest_connection(group_row.organization_id,group_row.id,p_name,p_email,p_phone,'',p_preferred_contact,true,now());
  IF guest.id IS NOT NULL THEN UPDATE public.circle_guest_rsvps SET connection_id=cid,updated_at=now() WHERE id=guest.id; END IF;
  IF listing.id IS NOT NULL THEN
    SELECT id INTO interest_id FROM public.circle_join_interests WHERE listing_id=listing.id AND connection_id=cid ORDER BY created_at DESC LIMIT 1;
    IF interest_id IS NULL THEN
      INSERT INTO public.circle_join_interests(organization_id,listing_id,name,contact,message,status,connection_id)
      VALUES(group_row.organization_id,listing.id,trim(p_name),CASE WHEN trim(p_email)<>'' THEN lower(trim(p_email)) ELSE trim(p_phone) END,left(trim(p_message),1000),'new',cid)
      RETURNING id INTO interest_id;
    ELSE
      UPDATE public.circle_join_interests SET name=trim(p_name),contact=CASE WHEN trim(p_email)<>'' THEN lower(trim(p_email)) ELSE trim(p_phone) END,message=left(trim(p_message),1000),status='new',updated_at=now() WHERE id=interest_id;
    END IF;
  END IF;
  RETURN jsonb_build_object('ok',true,'connectionId',cid,'interestId',interest_id);
END;
$$;

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
  cid:=public.circle_upsert_guest_connection(g.organization_id,g.cell_group_id,p_name,p_email,p_phone,'',p_preferred_contact,p_consent,CASE WHEN p_consent THEN now() ELSE NULL END);
  INSERT INTO public.circle_guest_rsvps(organization_id,gathering_id,guest_name,email,phone,normalized_contact,status,attended_at,connection_id)
  VALUES(g.organization_id,g.id,trim(p_name),lower(trim(p_email)),trim(p_phone),contact_key,'attending',now(),cid)
  ON CONFLICT(gathering_id,normalized_contact) DO UPDATE SET guest_name=excluded.guest_name,email=excluded.email,phone=excluded.phone,status='attending',attended_at=now(),connection_id=excluded.connection_id,updated_at=now()
  RETURNING id INTO rid;
  UPDATE public.circle_guest_connections SET status=CASE WHEN status IN ('new','contacted') THEN 'visited' ELSE status END,last_activity_at=now(),updated_at=now() WHERE id=cid;
  RETURN jsonb_build_object('ok',true,'guestRsvpId',rid,'connectionId',cid);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_connections(p_cell_group_id UUID DEFAULT NULL,p_filter TEXT DEFAULT 'active')
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',c.id,'organizationId',c.organization_id,'groupId',c.cell_group_id,'groupName',cg.name,
    'name',c.guest_name,'email',c.email,'phone',c.phone,'preferredContact',c.preferred_contact,
    'followUpOptIn',c.follow_up_opt_in,'consentedAt',c.consented_at,'status',c.status,
    'claimedByPersonId',c.claimed_by_person_id,'claimedByName',concat_ws(' ',cp.first_name,cp.last_name),
    'convertedPersonId',c.converted_person_id,'lastActivityAt',c.last_activity_at,
    'rsvpCount',(SELECT count(*) FROM public.circle_guest_rsvps r WHERE r.connection_id=c.id),
    'interestCount',(SELECT count(*) FROM public.circle_join_interests i WHERE i.connection_id=c.id),
    'attended',EXISTS(SELECT 1 FROM public.circle_guest_rsvps r WHERE r.connection_id=c.id AND r.attended_at IS NOT NULL)
  ) ORDER BY c.last_activity_at DESC),'[]'::jsonb)
  FROM public.circle_guest_connections c
  JOIN public.cell_groups cg ON cg.id=c.cell_group_id
  LEFT JOIN public.people cp ON cp.id=c.claimed_by_person_id
  WHERE (p_cell_group_id IS NULL OR c.cell_group_id=p_cell_group_id)
    AND (public.circle_is_org_admin(c.organization_id) OR public.circle_can_lead_group(c.cell_group_id))
    AND CASE p_filter
      WHEN 'attention' THEN c.follow_up_opt_in AND c.status='new'
      WHEN 'active' THEN c.status IN ('new','contacted','visited')
      WHEN 'connected' THEN c.status='connected'
      WHEN 'closed' THEN c.status='closed'
      ELSE true END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_connection(p_connection_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.circle_guest_connections%ROWTYPE; result JSONB;
BEGIN
  SELECT * INTO c FROM public.circle_guest_connections WHERE id=p_connection_id;
  IF c.id IS NULL OR NOT (public.circle_is_org_admin(c.organization_id) OR public.circle_can_lead_group(c.cell_group_id)) THEN RAISE EXCEPTION 'Connection not available'; END IF;
  SELECT jsonb_build_object(
    'id',c.id,'organizationId',c.organization_id,'groupId',c.cell_group_id,'groupName',cg.name,
    'name',c.guest_name,'email',c.email,'phone',c.phone,'preferredContact',c.preferred_contact,
    'followUpOptIn',c.follow_up_opt_in,'consentedAt',c.consented_at,'status',c.status,
    'claimedByPersonId',c.claimed_by_person_id,'claimedByName',concat_ws(' ',cp.first_name,cp.last_name),
    'convertedPersonId',c.converted_person_id,'lastActivityAt',c.last_activity_at,
    'rsvps',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'gatheringId',r.gathering_id,'title',g.title,'startsAt',g.starts_at,'status',r.status,'attendedAt',r.attended_at) ORDER BY g.starts_at DESC) FROM public.circle_guest_rsvps r JOIN public.circle_gatherings g ON g.id=r.gathering_id WHERE r.connection_id=c.id),'[]'::jsonb),
    'interests',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',i.id,'message',i.message,'status',i.status,'createdAt',i.created_at) ORDER BY i.created_at DESC) FROM public.circle_join_interests i WHERE i.connection_id=c.id),'[]'::jsonb),
    'activities',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',a.id,'type',a.activity_type,'body',a.body,'createdAt',a.created_at) ORDER BY a.created_at DESC) FROM public.circle_guest_connection_activities a WHERE a.connection_id=c.id),'[]'::jsonb)
  ) INTO result FROM public.cell_groups cg LEFT JOIN public.people cp ON cp.id=c.claimed_by_person_id WHERE cg.id=c.cell_group_id;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_circle_connection(p_connection_id UUID,p_action TEXT,p_note TEXT DEFAULT '')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.circle_guest_connections%ROWTYPE; current_person UUID; next_status TEXT; activity TEXT;
BEGIN
  SELECT * INTO c FROM public.circle_guest_connections WHERE id=p_connection_id FOR UPDATE;
  IF c.id IS NULL OR NOT (public.circle_is_org_admin(c.organization_id) OR public.circle_can_lead_group(c.cell_group_id)) THEN RAISE EXCEPTION 'Leader access required'; END IF;
  current_person:=public.circle_current_person_id(c.organization_id);
  IF p_action='claim' THEN
    IF current_person IS NULL OR NOT EXISTS(SELECT 1 FROM public.cell_groups cg LEFT JOIN public.cell_group_members gm ON gm.cell_group_id=cg.id AND gm.person_id=current_person WHERE cg.id=c.cell_group_id AND (cg.leader_person_id=current_person OR gm.role='Leader')) THEN RAISE EXCEPTION 'A linked Circle leader is required to claim this guest'; END IF;
    UPDATE public.circle_guest_connections SET claimed_by_person_id=current_person,updated_at=now() WHERE id=c.id; activity:='claimed';
  ELSIF p_action='unclaim' THEN
    UPDATE public.circle_guest_connections SET claimed_by_person_id=NULL,updated_at=now() WHERE id=c.id; activity:='unclaimed';
  ELSIF p_action='contacted' THEN
    next_status:=CASE WHEN c.status='new' THEN 'contacted' ELSE c.status END;
    UPDATE public.circle_guest_connections SET status=next_status,last_activity_at=now(),updated_at=now() WHERE id=c.id; activity:='contacted';
  ELSIF p_action='close' THEN
    UPDATE public.circle_guest_connections SET status='closed',last_activity_at=now(),updated_at=now() WHERE id=c.id; activity:='status_changed';
  ELSIF p_action='reopen' THEN
    next_status:=CASE WHEN EXISTS(SELECT 1 FROM public.circle_guest_rsvps r WHERE r.connection_id=c.id AND r.attended_at IS NOT NULL) THEN 'visited' ELSE 'new' END;
    UPDATE public.circle_guest_connections SET status=next_status,last_activity_at=now(),updated_at=now() WHERE id=c.id; activity:='status_changed';
  ELSIF p_action='note' THEN
    IF nullif(trim(p_note),'') IS NULL THEN RAISE EXCEPTION 'Note cannot be empty'; END IF; activity:='note';
    UPDATE public.circle_guest_connections SET last_activity_at=now(),updated_at=now() WHERE id=c.id;
  ELSE RAISE EXCEPTION 'Unsupported connection action'; END IF;
  INSERT INTO public.circle_guest_connection_activities(organization_id,connection_id,activity_type,body,created_by)
  VALUES(c.organization_id,c.id,activity,left(trim(COALESCE(p_note,'')),2000),auth.uid());
  RETURN public.get_circle_connection(c.id);
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_circle_connection(
  p_connection_id UUID,p_person_id UUID DEFAULT NULL,p_first_name TEXT DEFAULT '',p_last_name TEXT DEFAULT '',p_email TEXT DEFAULT '',p_phone TEXT DEFAULT ''
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.circle_guest_connections%ROWTYPE; pid UUID:=p_person_id; created_new BOOLEAN:=false;
BEGIN
  SELECT * INTO c FROM public.circle_guest_connections WHERE id=p_connection_id FOR UPDATE;
  IF c.id IS NULL OR NOT (public.circle_is_org_admin(c.organization_id) OR public.circle_can_lead_group(c.cell_group_id)) THEN RAISE EXCEPTION 'Leader access required'; END IF;
  IF c.converted_person_id IS NOT NULL THEN RETURN jsonb_build_object('personId',c.converted_person_id,'created',false,'alreadyConnected',true); END IF;
  IF pid IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.people p WHERE p.id=pid AND p.organization_id=c.organization_id) THEN RAISE EXCEPTION 'Person is outside this organization'; END IF;
  IF pid IS NULL THEN
    SELECT p.id INTO pid FROM public.people p WHERE p.organization_id=c.organization_id AND ((COALESCE(NULLIF(trim(p_email),''),c.email)<>'' AND lower(p.email)=lower(COALESCE(NULLIF(trim(p_email),''),c.email))) OR (COALESCE(NULLIF(trim(p_phone),''),c.phone)<>'' AND p.phone=COALESCE(NULLIF(trim(p_phone),''),c.phone))) ORDER BY p.created_at LIMIT 1;
    IF pid IS NOT NULL THEN RAISE EXCEPTION 'A matching SheepCount person already exists. Select that person instead'; END IF;
    IF nullif(trim(p_first_name),'') IS NULL OR nullif(trim(p_last_name),'') IS NULL THEN RAISE EXCEPTION 'First and last name are required for a new visitor'; END IF;
    INSERT INTO public.people(organization_id,household_id,first_name,last_name,email,phone,birthdate,role,status,membership_type,evangelism_stage,is_prospect,join_date)
    VALUES(c.organization_id,NULL,trim(p_first_name),trim(p_last_name),lower(COALESCE(NULLIF(trim(p_email),''),c.email)),COALESCE(NULLIF(trim(p_phone),''),c.phone),NULL,'Single','Active','Prospect','Small Group',true,current_date)
    RETURNING id INTO pid; created_new:=true;
  END IF;
  INSERT INTO public.cell_group_members(cell_group_id,person_id,role) VALUES(c.cell_group_id,pid,'Member') ON CONFLICT(cell_group_id,person_id) DO NOTHING;
  UPDATE public.circle_guest_connections SET converted_person_id=pid,status='connected',last_activity_at=now(),updated_at=now() WHERE id=c.id;
  UPDATE public.circle_guest_rsvps SET converted_person_id=pid,updated_at=now() WHERE connection_id=c.id;
  UPDATE public.circle_join_interests SET status='closed',updated_at=now() WHERE connection_id=c.id;
  INSERT INTO public.circle_guest_connection_activities(organization_id,connection_id,activity_type,body,created_by)
  VALUES(c.organization_id,c.id,'converted',CASE WHEN created_new THEN 'Registered as a SheepCount visitor.' ELSE 'Matched to an existing SheepCount person.' END,auth.uid());
  RETURN jsonb_build_object('personId',pid,'created',created_new,'alreadyConnected',false);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_connection_attention_count()
RETURNS INT LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT count(*)::int FROM public.circle_guest_connections c
  WHERE c.follow_up_opt_in AND c.status='new'
    AND (public.circle_is_org_admin(c.organization_id) OR public.circle_can_lead_group(c.cell_group_id));
$$;

-- Attendance promotes selected staged guests without changing consent.
CREATE OR REPLACE FUNCTION public.record_circle_attendance(p_gathering_id UUID,p_person_ids UUID[],p_guest_rsvp_ids UUID[] DEFAULT ARRAY[]::UUID[])
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE g public.circle_gatherings%ROWTYPE; grp public.cell_groups%ROWTYPE; sid UUID; leader_name TEXT;
BEGIN
  SELECT * INTO g FROM public.circle_gatherings WHERE id=p_gathering_id; IF g.id IS NULL OR NOT public.circle_can_lead_group(g.cell_group_id) THEN RAISE EXCEPTION 'Leader access required'; END IF; SELECT * INTO grp FROM public.cell_groups WHERE id=g.cell_group_id;
  IF EXISTS(SELECT 1 FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) x WHERE NOT EXISTS(SELECT 1 FROM public.people p WHERE p.id=x AND p.organization_id=g.organization_id)) THEN RAISE EXCEPTION 'An attendee is outside this organization'; END IF;
  SELECT concat_ws(' ',p.first_name,p.last_name) INTO leader_name FROM public.people p WHERE p.id=COALESCE(g.leader_person_id,grp.leader_person_id); leader_name:=COALESCE(nullif(leader_name,''),'Circle leader');
  INSERT INTO public.cell_group_sessions(organization_id,cell_group_id,session_date,leader_person_id,leader_name,location) VALUES(g.organization_id,g.cell_group_id,(g.starts_at AT TIME ZONE 'UTC')::date,COALESCE(g.leader_person_id,grp.leader_person_id),leader_name,g.location)
  ON CONFLICT(cell_group_id,session_date) DO UPDATE SET leader_person_id=excluded.leader_person_id,leader_name=excluded.leader_name,location=excluded.location,updated_at=now() RETURNING id INTO sid;
  DELETE FROM public.cell_group_session_attendees WHERE session_id=sid;
  INSERT INTO public.cell_group_session_attendees(session_id,person_id) SELECT sid,x FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) x ON CONFLICT(session_id,person_id) DO NOTHING;
  UPDATE public.circle_guest_rsvps SET attended_at=now(),updated_at=now() WHERE gathering_id=g.id AND id=ANY(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[]));
  UPDATE public.circle_guest_connections c SET status=CASE WHEN c.status IN ('new','contacted') THEN 'visited' ELSE c.status END,last_activity_at=now(),updated_at=now()
    WHERE c.id IN (SELECT r.connection_id FROM public.circle_guest_rsvps r WHERE r.gathering_id=g.id AND r.id=ANY(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[])) AND r.connection_id IS NOT NULL);
  UPDATE public.circle_gatherings SET attendance_session_id=sid,status='completed',updated_at=now() WHERE id=g.id;
  RETURN sid;
END;
$$;

REVOKE ALL ON FUNCTION public.circle_upsert_guest_connection(UUID,UUID,TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN,TIMESTAMPTZ) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.request_circle_connection(UUID,UUID,TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_circle_connection(UUID,UUID,TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.stage_circle_walk_in(UUID,TEXT,TEXT,TEXT,TEXT,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.stage_circle_walk_in(UUID,TEXT,TEXT,TEXT,TEXT,BOOLEAN) TO authenticated;
REVOKE ALL ON FUNCTION public.get_circle_connections(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_circle_connections(UUID,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.get_circle_connection(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_circle_connection(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.update_circle_connection(UUID,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_circle_connection(UUID,TEXT,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.resolve_circle_connection(UUID,UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.resolve_circle_connection(UUID,UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.get_circle_connection_attention_count() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_circle_connection_attention_count() TO authenticated;

COMMIT;
