BEGIN;

CREATE TABLE IF NOT EXISTS public.circle_group_signups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'unassigned' CHECK (status IN ('unassigned','placed')),
  facebook_contact TEXT NOT NULL DEFAULT '' CHECK (char_length(facebook_contact) <= 300),
  normalized_facebook_contact TEXT NOT NULL DEFAULT '',
  birthdate_discrepancy DATE,
  source TEXT NOT NULL CHECK (source IN ('public','guest_self','leader_conversion')),
  source_guest_connection_id UUID REFERENCES public.circle_guest_connections(id) ON DELETE SET NULL,
  consented_at TIMESTAMPTZ NOT NULL,
  consent_recorded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  placed_cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE SET NULL,
  placed_by_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  placed_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  placed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (
    (status='unassigned' AND placed_cell_group_id IS NULL AND placed_at IS NULL) OR
    (status='placed' AND placed_cell_group_id IS NOT NULL AND placed_at IS NOT NULL)
  )
);

CREATE TABLE IF NOT EXISTS public.circle_group_signup_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signup_id UUID NOT NULL REFERENCES public.circle_group_signups(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('submitted','refreshed','placed')),
  source TEXT CHECK (source IN ('public','guest_self','leader_conversion')),
  source_guest_connection_id UUID REFERENCES public.circle_guest_connections(id) ON DELETE SET NULL,
  facebook_contact TEXT NOT NULL DEFAULT '' CHECK (char_length(facebook_contact) <= 300),
  consented_at TIMESTAMPTZ,
  consent_recorded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE SET NULL,
  actor_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS circle_group_signup_events_signup_idx
  ON public.circle_group_signup_events(signup_id,created_at);

CREATE UNIQUE INDEX IF NOT EXISTS circle_group_signups_unassigned_person_idx
  ON public.circle_group_signups(organization_id,person_id)
  WHERE status='unassigned';
CREATE UNIQUE INDEX IF NOT EXISTS circle_group_signups_unassigned_facebook_idx
  ON public.circle_group_signups(organization_id,normalized_facebook_contact)
  WHERE status='unassigned' AND normalized_facebook_contact<>'';
CREATE INDEX IF NOT EXISTS circle_group_signups_queue_idx
  ON public.circle_group_signups(organization_id,status,created_at DESC);

ALTER TABLE public.circle_group_signups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_group_signup_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Organization leaders read Cell Group signups" ON public.circle_group_signups;
CREATE POLICY "Organization leaders read Cell Group signups"
ON public.circle_group_signups FOR SELECT TO authenticated
USING (public.circle_can_lead_organization(organization_id));

CREATE OR REPLACE FUNCTION public.circle_normalize_signup_phone(p_phone TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path='' AS $$
  SELECT regexp_replace(COALESCE(p_phone,''), '[^0-9+]', '', 'g');
$$;

CREATE OR REPLACE FUNCTION public.circle_normalize_facebook_contact(p_contact TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path='' AS $$
  SELECT trim(trailing '/' FROM regexp_replace(
    lower(trim(COALESCE(p_contact,''))),
    '^(https?://)?(www\.)?(facebook\.com/|m\.me/|@)',
    ''
  ));
$$;

CREATE OR REPLACE FUNCTION public.circle_create_group_signup(
  p_organization_id UUID,
  p_first_name TEXT,
  p_last_name TEXT,
  p_birthdate DATE,
  p_phone TEXT,
  p_facebook_contact TEXT,
  p_source TEXT,
  p_guest_connection_id UUID DEFAULT NULL,
  p_consent_recorded_by UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_first_name TEXT:=trim(COALESCE(p_first_name,''));
  v_last_name TEXT:=trim(COALESCE(p_last_name,''));
  v_phone TEXT:=public.circle_normalize_signup_phone(p_phone);
  v_facebook TEXT:=public.circle_normalize_facebook_contact(p_facebook_contact);
  v_phone_person UUID;
  v_facebook_person UUID;
  v_person_id UUID;
  v_signup_id UUID;
  v_group_id UUID;
  v_existing_birthdate DATE;
  v_match_count INT;
BEGIN
  IF p_organization_id IS NULL OR char_length(v_first_name) NOT BETWEEN 1 AND 80
    OR char_length(v_last_name) NOT BETWEEN 1 AND 80
    OR p_birthdate IS NULL OR p_birthdate>current_date
    OR p_birthdate<DATE '1900-01-01'
    OR (v_phone='' AND v_facebook='')
    OR (v_phone<>'' AND trim(COALESCE(p_phone,'')) !~ '^[+0-9() .-]+$')
    OR (v_phone<>'' AND v_phone !~ '^\+?[0-9]{7,15}$')
    OR (v_facebook<>'' AND trim(COALESCE(p_facebook_contact,'')) !~* '^(@?[a-z0-9._-]{3,100}|(https?://)?(www\.)?(facebook\.com|m\.me)/[^[:space:]]{1,200})/?$')
    OR char_length(COALESCE(p_phone,''))>40
    OR char_length(COALESCE(p_facebook_contact,''))>300
    OR p_source NOT IN ('public','guest_self','leader_conversion') THEN
    RAISE EXCEPTION 'Signup details are invalid';
  END IF;

  -- Serialize retries and contact-based matches so concurrent submissions are idempotent.
  IF v_phone<>'' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':phone:'||v_phone,0));
  END IF;
  IF v_facebook<>'' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':facebook:'||v_facebook,0));
  END IF;

  IF v_phone<>'' THEN
    SELECT count(DISTINCT person.id),(array_agg(DISTINCT person.id))[1]
      INTO v_match_count,v_phone_person
    FROM public.people person
    WHERE person.organization_id=p_organization_id
      AND public.circle_normalize_signup_phone(person.phone)=v_phone;
    IF v_match_count>1 THEN RAISE EXCEPTION 'Signup could not be completed'; END IF;
  END IF;

  IF v_facebook<>'' THEN
    SELECT count(DISTINCT signup.person_id),(array_agg(DISTINCT signup.person_id))[1]
      INTO v_match_count,v_facebook_person
    FROM public.circle_group_signups signup
    WHERE signup.organization_id=p_organization_id
      AND signup.normalized_facebook_contact=v_facebook;
    IF v_match_count>1 THEN RAISE EXCEPTION 'Signup could not be completed'; END IF;
  END IF;

  IF v_phone_person IS NOT NULL AND v_facebook_person IS NOT NULL
    AND v_phone_person<>v_facebook_person THEN
    RAISE EXCEPTION 'Signup could not be completed';
  END IF;
  v_person_id:=COALESCE(v_phone_person,v_facebook_person);

  IF v_person_id IS NULL THEN
    INSERT INTO public.people(
      organization_id,household_id,first_name,last_name,email,phone,birthdate,
      role,status,membership_type,evangelism_stage,is_prospect,join_date
    ) VALUES(
      p_organization_id,NULL,v_first_name,v_last_name,'',trim(COALESCE(p_phone,'')),p_birthdate,
      'Single','Active','Prospect','Small Group',true,current_date
    ) RETURNING id INTO v_person_id;
  END IF;

  SELECT birthdate INTO v_existing_birthdate FROM public.people WHERE id=v_person_id;

  SELECT membership.cell_group_id INTO v_group_id
  FROM public.cell_group_members membership
  JOIN public.cell_groups group_row ON group_row.id=membership.cell_group_id
  WHERE membership.person_id=v_person_id
    AND group_row.organization_id=p_organization_id
    AND group_row.status='active'
  ORDER BY membership.created_at
  LIMIT 1;

  IF v_group_id IS NOT NULL THEN
    UPDATE public.circle_group_signups
    SET status='placed',placed_cell_group_id=v_group_id,placed_at=COALESCE(placed_at,now()),updated_at=now()
    WHERE organization_id=p_organization_id AND person_id=v_person_id AND status='unassigned'
    RETURNING id INTO v_signup_id;
    IF v_signup_id IS NOT NULL THEN
      INSERT INTO public.circle_group_signup_events(signup_id,event_type,cell_group_id)
      VALUES(v_signup_id,'placed',v_group_id);
    END IF;
    RETURN jsonb_build_object('ok',true);
  END IF;

  SELECT id INTO v_signup_id
  FROM public.circle_group_signups
  WHERE organization_id=p_organization_id AND person_id=v_person_id AND status='unassigned'
  FOR UPDATE;

  IF v_signup_id IS NULL THEN
    INSERT INTO public.circle_group_signups(
      organization_id,person_id,facebook_contact,normalized_facebook_contact,
      birthdate_discrepancy,source,source_guest_connection_id,consented_at,consent_recorded_by
    ) VALUES(
      p_organization_id,v_person_id,trim(COALESCE(p_facebook_contact,'')),v_facebook,
      CASE WHEN v_existing_birthdate IS DISTINCT FROM p_birthdate THEN p_birthdate END,
      p_source,p_guest_connection_id,now(),p_consent_recorded_by
    ) RETURNING id INTO v_signup_id;
    INSERT INTO public.circle_group_signup_events(
      signup_id,event_type,source,source_guest_connection_id,facebook_contact,
      consented_at,consent_recorded_by
    ) VALUES(
      v_signup_id,'submitted',p_source,p_guest_connection_id,trim(COALESCE(p_facebook_contact,'')),
      now(),p_consent_recorded_by
    );
  ELSE
    UPDATE public.circle_group_signups
    SET facebook_contact=CASE WHEN v_facebook<>'' THEN trim(p_facebook_contact) ELSE facebook_contact END,
        normalized_facebook_contact=CASE WHEN v_facebook<>'' THEN v_facebook ELSE normalized_facebook_contact END,
        source=p_source,
        birthdate_discrepancy=CASE WHEN v_existing_birthdate IS DISTINCT FROM p_birthdate THEN p_birthdate END,
        source_guest_connection_id=COALESCE(p_guest_connection_id,source_guest_connection_id),
        consented_at=now(),consent_recorded_by=p_consent_recorded_by,updated_at=now()
    WHERE id=v_signup_id;
    INSERT INTO public.circle_group_signup_events(
      signup_id,event_type,source,source_guest_connection_id,facebook_contact,
      consented_at,consent_recorded_by
    ) VALUES(
      v_signup_id,'refreshed',p_source,p_guest_connection_id,trim(COALESCE(p_facebook_contact,'')),
      now(),p_consent_recorded_by
    );
  END IF;

  RETURN jsonb_build_object('ok',true);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_circle_group_signup(
  p_org_slug TEXT,
  p_first_name TEXT,
  p_last_name TEXT,
  p_birthdate DATE,
  p_phone TEXT,
  p_facebook_contact TEXT,
  p_consent BOOLEAN,
  p_guest_rsvp_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_organization_id UUID;
  v_guest_connection_id UUID;
  v_source TEXT:='public';
BEGIN
  IF NOT COALESCE(p_consent,false) THEN RAISE EXCEPTION 'Consent is required'; END IF;
  IF char_length(trim(COALESCE(p_org_slug,''))) NOT BETWEEN 1 AND 120 THEN
    RAISE EXCEPTION 'Signup is unavailable';
  END IF;
  SELECT space.organization_id INTO v_organization_id
  FROM public.circle_public_spaces space
  JOIN public.organizations organization ON organization.id=space.organization_id
  WHERE organization.slug=p_org_slug AND space.is_published;
  IF v_organization_id IS NULL THEN RAISE EXCEPTION 'Signup is unavailable'; END IF;

  IF p_guest_rsvp_id IS NOT NULL THEN
    SELECT rsvp.connection_id INTO v_guest_connection_id
    FROM public.circle_guest_rsvps rsvp
    WHERE rsvp.id=p_guest_rsvp_id AND rsvp.organization_id=v_organization_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Signup could not be completed'; END IF;
    v_source:='guest_self';
  END IF;

  RETURN public.circle_create_group_signup(
    v_organization_id,p_first_name,p_last_name,p_birthdate,p_phone,p_facebook_contact,
    v_source,v_guest_connection_id,NULL
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_group_signups(
  p_organization_id UUID,
  p_status TEXT DEFAULT 'unassigned'
) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF p_status NOT IN ('unassigned','placed')
    OR NOT public.circle_can_lead_organization(p_organization_id) THEN
    RAISE EXCEPTION 'Leader access required';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id',signup.id,'organizationId',signup.organization_id,'personId',person.id,
      'firstName',person.first_name,'lastName',person.last_name,
      'fullName',concat_ws(' ',person.first_name,person.last_name),
      'birthdate',person.birthdate,'phone',person.phone,
      'birthdateDiscrepancy',signup.birthdate_discrepancy,
      'facebookContact',signup.facebook_contact,'status',signup.status,'source',signup.source,
      'sourceGuestConnectionId',signup.source_guest_connection_id,
      'consentedAt',signup.consented_at,'placedGroupId',signup.placed_cell_group_id,
      'placedGroupName',group_row.name,'placedByPersonId',signup.placed_by_person_id,
      'placedAt',signup.placed_at,'createdAt',signup.created_at,'updatedAt',signup.updated_at
    ) ORDER BY signup.created_at)
    FROM public.circle_group_signups signup
    JOIN public.people person ON person.id=signup.person_id
    LEFT JOIN public.cell_groups group_row ON group_row.id=signup.placed_cell_group_id
    WHERE signup.organization_id=p_organization_id AND signup.status=p_status
  ),'[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_group_signup_attention_count(p_organization_id UUID)
RETURNS INT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT public.circle_can_lead_organization(p_organization_id) THEN RETURN 0; END IF;
  RETURN (SELECT count(*)::INT FROM public.circle_group_signups
    WHERE organization_id=p_organization_id AND status='unassigned');
END;
$$;

CREATE OR REPLACE FUNCTION public.convert_guest_connection_to_group_signup(
  p_connection_id UUID,
  p_first_name TEXT,
  p_last_name TEXT,
  p_birthdate DATE,
  p_phone TEXT,
  p_facebook_contact TEXT,
  p_consent_confirmed BOOLEAN
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_connection public.circle_guest_connections%ROWTYPE; v_phone TEXT;
BEGIN
  SELECT * INTO v_connection FROM public.circle_guest_connections WHERE id=p_connection_id;
  IF v_connection.id IS NULL OR NOT (
    public.circle_is_org_admin(v_connection.organization_id) OR
    (v_connection.cell_group_id IS NULL AND public.circle_can_lead_organization(v_connection.organization_id)) OR
    (v_connection.cell_group_id IS NOT NULL AND public.circle_can_lead_group(v_connection.cell_group_id))
  ) THEN RAISE EXCEPTION 'Leader access required'; END IF;
  IF NOT COALESCE(p_consent_confirmed,false) THEN RAISE EXCEPTION 'Consent confirmation is required'; END IF;
  v_phone:=COALESCE(NULLIF(trim(p_phone),''),v_connection.phone);
  RETURN public.circle_create_group_signup(
    v_connection.organization_id,p_first_name,p_last_name,p_birthdate,v_phone,p_facebook_contact,
    'leader_conversion',v_connection.id,auth.uid()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.place_circle_group_signup(
  p_signup_id UUID,
  p_cell_group_id UUID
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_signup public.circle_group_signups%ROWTYPE; v_group public.cell_groups%ROWTYPE; v_person UUID;
BEGIN
  SELECT * INTO v_signup FROM public.circle_group_signups WHERE id=p_signup_id FOR UPDATE;
  IF v_signup.id IS NULL OR v_signup.status<>'unassigned' THEN
    RAISE EXCEPTION 'This signup has already been placed';
  END IF;
  SELECT * INTO v_group FROM public.cell_groups
  WHERE id=p_cell_group_id AND organization_id=v_signup.organization_id AND status='active';
  IF v_group.id IS NULL THEN RAISE EXCEPTION 'Choose an active Circle'; END IF;
  IF NOT (public.circle_is_org_admin(v_signup.organization_id) OR public.circle_can_lead_group(v_group.id)) THEN
    RAISE EXCEPTION 'You can place people only into Circles you lead';
  END IF;
  v_person:=public.circle_current_person_id(v_signup.organization_id);
  INSERT INTO public.cell_group_members(cell_group_id,person_id,role)
  VALUES(v_group.id,v_signup.person_id,'Member')
  ON CONFLICT(cell_group_id,person_id) DO NOTHING;
  UPDATE public.circle_group_signups SET
    status='placed',placed_cell_group_id=v_group.id,placed_by_person_id=v_person,
    placed_by_user_id=auth.uid(),placed_at=now(),updated_at=now()
  WHERE id=v_signup.id;
  INSERT INTO public.circle_group_signup_events(
    signup_id,event_type,cell_group_id,actor_person_id,actor_user_id
  ) VALUES(v_signup.id,'placed',v_group.id,v_person,auth.uid());
END;
$$;

REVOKE ALL ON FUNCTION public.circle_normalize_signup_phone(TEXT) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.circle_normalize_facebook_contact(TEXT) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.circle_create_group_signup(UUID,TEXT,TEXT,DATE,TEXT,TEXT,TEXT,UUID,UUID) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.submit_circle_group_signup(TEXT,TEXT,TEXT,DATE,TEXT,TEXT,BOOLEAN,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_circle_group_signup(TEXT,TEXT,TEXT,DATE,TEXT,TEXT,BOOLEAN,UUID) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.get_circle_group_signups(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_circle_group_signups(UUID,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.get_circle_group_signup_attention_count(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_circle_group_signup_attention_count(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.convert_guest_connection_to_group_signup(UUID,TEXT,TEXT,DATE,TEXT,TEXT,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.convert_guest_connection_to_group_signup(UUID,TEXT,TEXT,DATE,TEXT,TEXT,BOOLEAN) TO authenticated;
REVOKE ALL ON FUNCTION public.place_circle_group_signup(UUID,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.place_circle_group_signup(UUID,UUID) TO authenticated;

COMMIT;
