BEGIN;

-- Circles access is independent from SheepCount membership. Only tenant admins
-- retain a dual-use organization membership.
CREATE OR REPLACE FUNCTION public.circle_has_app_access(p_organization_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.organization_id=p_organization_id AND om.user_id=auth.uid()
      AND om.status='active' AND om.role='admin'
  ) OR EXISTS (
    SELECT 1 FROM public.circle_user_links link
    WHERE link.organization_id=p_organization_id AND link.user_id=auth.uid()
      AND link.status='active'
  );
$$;

CREATE OR REPLACE FUNCTION public.circle_can_access_gathering(p_gathering_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.circle_gatherings gathering
    WHERE gathering.id=p_gathering_id AND (
      (gathering.scope='circle' AND public.circle_can_access_group(gathering.cell_group_id)) OR
      (gathering.scope='organization' AND public.circle_has_app_access(gathering.organization_id))
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.get_my_circle_context()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_user UUID:=auth.uid(); v_org UUID; v_person UUID; v_admin BOOLEAN:=false;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT om.organization_id,true INTO v_org,v_admin FROM public.organization_members om
 WHERE om.user_id=v_user AND om.status='active' AND om.role='admin' ORDER BY om.created_at LIMIT 1;
 IF v_org IS NULL THEN
  SELECT link.organization_id,link.person_id INTO v_org,v_person FROM public.circle_user_links link
  WHERE link.user_id=v_user AND link.status='active' ORDER BY link.created_at LIMIT 1;
 ELSE
  SELECT link.person_id INTO v_person FROM public.circle_user_links link
  WHERE link.organization_id=v_org AND link.user_id=v_user AND link.status='active' LIMIT 1;
 END IF;
 IF v_org IS NULL THEN RAISE EXCEPTION 'No active Circles organization is linked to this account'; END IF;
 RETURN (SELECT jsonb_build_object(
  'organization',jsonb_build_object('id',o.id,'name',o.name,'slug',o.slug,'image',o.image,'status',o.status),
  'circlesEnabled',true,'isAdmin',v_admin,'isApprovedLeader',public.circle_is_approved_leader(v_org,v_person),'personId',v_person,
  'profile',jsonb_build_object('id',coalesce(profile.id,v_user),'firstName',coalesce(profile.first_name,person.first_name),'lastName',coalesce(profile.last_name,person.last_name),'avatarUrl',profile.avatar_url),
  'groups',coalesce((SELECT jsonb_agg(jsonb_build_object('id',cg.id,'name',cg.name,'description',cg.description,'location',cg.location,'leaderPersonId',cg.leader_person_id,'status',cg.status,'role',CASE WHEN v_admin THEN 'admin' WHEN member.role='Leader' OR cg.leader_person_id=v_person THEN 'leader' ELSE 'member' END) ORDER BY cg.name)
   FROM public.cell_groups cg LEFT JOIN public.cell_group_members member ON member.cell_group_id=cg.id AND member.person_id=v_person
   WHERE cg.organization_id=o.id AND cg.status='active' AND (v_admin OR member.id IS NOT NULL OR cg.leader_person_id=v_person)),'[]'::jsonb)
 ) FROM public.organizations o LEFT JOIN public.profiles profile ON profile.id=v_user LEFT JOIN public.people person ON person.id=v_person WHERE o.id=v_org);
END; $$;

CREATE OR REPLACE FUNCTION public.create_circle_group(
  p_name TEXT, p_description TEXT DEFAULT '', p_location TEXT DEFAULT '',
  p_leader_person_id UUID DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_org UUID; v_person UUID; v_admin BOOLEAN:=false; v_leader UUID; v_group UUID;
BEGIN
  SELECT om.organization_id,true INTO v_org,v_admin FROM public.organization_members om
  WHERE om.user_id=auth.uid() AND om.status='active' AND om.role='admin'
  ORDER BY om.created_at LIMIT 1;
  IF v_org IS NULL THEN
    SELECT link.organization_id,link.person_id INTO v_org,v_person
    FROM public.circle_user_links link
    WHERE link.user_id=auth.uid() AND link.status='active' ORDER BY link.created_at LIMIT 1;
  END IF;
  IF v_org IS NULL OR NOT public.circle_org_enabled(v_org) THEN RAISE EXCEPTION 'An active Circles organization is required'; END IF;
  IF nullif(trim(p_name),'') IS NULL THEN RAISE EXCEPTION 'Circle name is required'; END IF;
  IF v_admin THEN
    v_leader:=p_leader_person_id;
    IF v_leader IS NULL OR NOT public.circle_is_approved_leader(v_org,v_leader) THEN RAISE EXCEPTION 'Choose an approved Cell Group Leader'; END IF;
  ELSE
    IF v_person IS NULL OR NOT public.circle_is_approved_leader(v_org,v_person) THEN RAISE EXCEPTION 'Cell Group Leader approval is required'; END IF;
    IF p_leader_person_id IS NOT NULL AND p_leader_person_id<>v_person THEN RAISE EXCEPTION 'Leaders can create a Circle only for themselves'; END IF;
    v_leader:=v_person;
  END IF;
  INSERT INTO public.cell_groups(organization_id,name,description,location,leader_person_id)
  VALUES(v_org,trim(p_name),trim(coalesce(p_description,'')),trim(coalesce(p_location,'')),v_leader) RETURNING id INTO v_group;
  INSERT INTO public.cell_group_members(cell_group_id,person_id,role) VALUES(v_group,v_leader,'Leader')
  ON CONFLICT(cell_group_id,person_id) DO UPDATE SET role='Leader';
  RETURN v_group;
END; $$;

CREATE TABLE public.circle_gathering_closeouts (
  gathering_id UUID PRIMARY KEY REFERENCES public.circle_gatherings(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  notes TEXT NOT NULL DEFAULT '' CHECK(char_length(notes)<=2000),
  finalized_at TIMESTAMPTZ,
  editable_until TIMESTAMPTZ,
  finalized_by UUID REFERENCES auth.users(id),
  updated_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK((finalized_at IS NULL AND editable_until IS NULL) OR (finalized_at IS NOT NULL AND editable_until=finalized_at+interval '7 days'))
);
ALTER TABLE public.circle_gathering_closeouts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Gathering managers read closeouts" ON public.circle_gathering_closeouts
FOR SELECT TO authenticated USING(public.circle_can_manage_gathering(gathering_id));
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON public.circle_gathering_closeouts FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.circle_gathering_closeouts TO authenticated;

CREATE OR REPLACE FUNCTION public.save_circle_gathering_closeout(
  p_gathering_id UUID, p_person_ids UUID[] DEFAULT ARRAY[]::UUID[],
  p_guest_rsvp_ids UUID[] DEFAULT ARRAY[]::UUID[], p_newcomers JSONB DEFAULT '[]'::jsonb,
  p_notes TEXT DEFAULT '', p_complete BOOLEAN DEFAULT false
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE g public.circle_gatherings%ROWTYPE; c public.circle_gathering_closeouts%ROWTYPE;
  item JSONB; first_name TEXT; last_name TEXT; birthday DATE; match_id UUID; match_status TEXT;
  match_count INT; people_ids UUID[]:=ARRAY[]::UUID[]; v_session_id UUID; group_row public.cell_groups%ROWTYPE; leader_name TEXT;
BEGIN
  SELECT * INTO g FROM public.circle_gatherings WHERE id=p_gathering_id FOR UPDATE;
  IF g.id IS NULL OR NOT public.circle_can_manage_gathering(g.id) THEN RAISE EXCEPTION 'Gathering manager access required'; END IF;
  SELECT * INTO c FROM public.circle_gathering_closeouts WHERE gathering_id=g.id FOR UPDATE;
  IF g.status='cancelled' THEN RAISE EXCEPTION 'A cancelled gathering cannot be closed out'; END IF;
  IF g.starts_at>now() THEN RAISE EXCEPTION 'Closeout is unavailable before the gathering begins'; END IF;
  IF g.status='completed' AND (c.editable_until IS NULL OR now()>=c.editable_until) THEN RAISE EXCEPTION 'This gathering closeout is permanently locked'; END IF;
  IF p_complete AND g.ends_at>=now() THEN RAISE EXCEPTION 'A gathering cannot be completed before it ends'; END IF;
  IF char_length(coalesce(p_notes,''))>2000 THEN RAISE EXCEPTION 'Notes must be 2,000 characters or fewer'; END IF;
  IF jsonb_typeof(coalesce(p_newcomers,'[]'::jsonb))<>'array' OR jsonb_array_length(coalesce(p_newcomers,'[]'::jsonb))>50 THEN RAISE EXCEPTION 'Newcomers must be an array of at most 50 records'; END IF;
  people_ids:=coalesce(p_person_ids,ARRAY[]::UUID[]);
  FOR item IN SELECT value FROM jsonb_array_elements(coalesce(p_newcomers,'[]'::jsonb)) LOOP
    first_name:=trim(coalesce(item->>'firstName','')); last_name:=trim(coalesce(item->>'lastName',''));
    BEGIN birthday:=(item->>'birthdate')::date; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Each newcomer needs a valid birthdate'; END;
    IF char_length(first_name) NOT BETWEEN 1 AND 80 OR char_length(last_name) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Newcomer names must be 1 to 80 characters'; END IF;
    IF birthday<DATE '1900-01-01' OR birthday>current_date THEN RAISE EXCEPTION 'Newcomer birthdate must be from 1900 through today'; END IF;
    SELECT count(*),(array_agg(id ORDER BY id))[1],min(status) INTO match_count,match_id,match_status FROM public.people
    WHERE organization_id=g.organization_id AND lower(trim(people.first_name))=lower(first_name)
      AND lower(trim(people.last_name))=lower(last_name) AND birthdate=birthday;
    IF match_count>1 THEN RAISE EXCEPTION 'Multiple People match this newcomer; resolve the duplicate in SheepCount'; END IF;
    IF match_count=1 AND lower(match_status)<>'active' THEN RAISE EXCEPTION 'This newcomer matches an inactive or exited Person; resolve it in SheepCount'; END IF;
    IF match_count=0 THEN
      INSERT INTO public.people(organization_id,first_name,last_name,birthdate,status,membership_type,evangelism_stage,is_prospect)
      VALUES(g.organization_id,first_name,last_name,birthday,'Active','Prospect','Small Group',true) RETURNING id INTO match_id;
      INSERT INTO public.circle_security_audit_events(organization_id,actor_user_id,action,target_type,target_id,result,request_id,metadata)
      VALUES(g.organization_id,auth.uid(),'attendance.newcomer_created','person',match_id::text,'success',gen_random_uuid()::text,jsonb_build_object('gatheringId',g.id));
    END IF;
    people_ids:=array_append(people_ids,match_id);
  END LOOP;
  SELECT coalesce(array_agg(DISTINCT id),ARRAY[]::UUID[]) INTO people_ids FROM unnest(people_ids) id;
  IF EXISTS(SELECT 1 FROM unnest(people_ids) id WHERE NOT EXISTS(SELECT 1 FROM public.people p WHERE p.id=id AND p.organization_id=g.organization_id AND lower(p.status)='active')) THEN RAISE EXCEPTION 'An attendee is not an active Person in this organization'; END IF;
  IF EXISTS(SELECT 1 FROM unnest(coalesce(p_guest_rsvp_ids,ARRAY[]::UUID[])) id WHERE NOT EXISTS(SELECT 1 FROM public.circle_guest_rsvps r WHERE r.id=id AND r.gathering_id=g.id)) THEN RAISE EXCEPTION 'A guest RSVP does not belong to this gathering'; END IF;
  IF g.scope='organization' THEN
    DELETE FROM public.circle_gathering_attendance_records WHERE gathering_id=g.id;
    INSERT INTO public.circle_gathering_attendance_records(organization_id,gathering_id,person_id,recorded_by) SELECT g.organization_id,g.id,id,auth.uid() FROM unnest(people_ids) id;
    INSERT INTO public.circle_gathering_attendance_records(organization_id,gathering_id,guest_rsvp_id,recorded_by) SELECT g.organization_id,g.id,id,auth.uid() FROM unnest(coalesce(p_guest_rsvp_ids,ARRAY[]::UUID[])) id;
  ELSE
    SELECT * INTO group_row FROM public.cell_groups WHERE id=g.cell_group_id;
    SELECT concat_ws(' ',p.first_name,p.last_name) INTO leader_name FROM public.people p WHERE p.id=coalesce(g.leader_person_id,group_row.leader_person_id);
    INSERT INTO public.cell_group_sessions(organization_id,cell_group_id,session_date,leader_person_id,leader_name,location)
    VALUES(g.organization_id,g.cell_group_id,(g.starts_at AT TIME ZONE 'UTC')::date,coalesce(g.leader_person_id,group_row.leader_person_id),coalesce(nullif(leader_name,''),'Circle leader'),g.location)
    ON CONFLICT(cell_group_id,session_date) DO UPDATE SET leader_person_id=excluded.leader_person_id,leader_name=excluded.leader_name,location=excluded.location,updated_at=now() RETURNING id INTO v_session_id;
    DELETE FROM public.cell_group_session_attendees attendee WHERE attendee.session_id=v_session_id;
    INSERT INTO public.cell_group_session_attendees(session_id,person_id) SELECT v_session_id,id FROM unnest(people_ids) id ON CONFLICT DO NOTHING;
  END IF;
  UPDATE public.circle_guest_rsvps SET attended_at=CASE WHEN id=ANY(coalesce(p_guest_rsvp_ids,ARRAY[]::UUID[])) THEN coalesce(attended_at,now()) ELSE NULL END,updated_at=now() WHERE gathering_id=g.id;
  INSERT INTO public.circle_gathering_closeouts(gathering_id,organization_id,notes,finalized_at,editable_until,finalized_by,updated_by)
  VALUES(g.id,g.organization_id,coalesce(p_notes,''),CASE WHEN p_complete THEN now() END,CASE WHEN p_complete THEN now()+interval '7 days' END,CASE WHEN p_complete THEN auth.uid() END,auth.uid())
  ON CONFLICT(gathering_id) DO UPDATE SET notes=excluded.notes,
    finalized_at=coalesce(circle_gathering_closeouts.finalized_at,excluded.finalized_at),
    editable_until=coalesce(circle_gathering_closeouts.editable_until,excluded.editable_until),
    finalized_by=coalesce(circle_gathering_closeouts.finalized_by,excluded.finalized_by),updated_by=auth.uid(),updated_at=now();
  UPDATE public.circle_gatherings SET attendance_session_id=coalesce(v_session_id,attendance_session_id),attendance_saved_at=now(),status=CASE WHEN p_complete THEN 'completed' ELSE status END,updated_at=now() WHERE id=g.id;
  RETURN public.get_circle_gathering_attendance(g.id);
END; $$;

CREATE OR REPLACE FUNCTION public.get_circle_gathering_attendance(p_gathering_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE g public.circle_gatherings%ROWTYPE; c public.circle_gathering_closeouts%ROWTYPE; ids JSONB;
BEGIN
 SELECT * INTO g FROM public.circle_gatherings WHERE id=p_gathering_id;
 IF g.id IS NULL OR NOT public.circle_can_manage_gathering(g.id) THEN RAISE EXCEPTION 'Gathering manager access required'; END IF;
 SELECT * INTO c FROM public.circle_gathering_closeouts WHERE gathering_id=g.id;
 SELECT coalesce(jsonb_agg(x.person_id),'[]'::jsonb) INTO ids FROM (
   SELECT r.person_id FROM public.circle_gathering_attendance_records r WHERE g.scope='organization' AND r.gathering_id=g.id AND r.person_id IS NOT NULL
   UNION SELECT a.person_id FROM public.cell_group_session_attendees a WHERE g.scope='circle' AND a.session_id=g.attendance_session_id
 ) x;
 RETURN jsonb_build_object('saved',g.attendance_saved_at IS NOT NULL,'status',g.status,'personIds',ids,
  'guestRsvpIds',coalesce((SELECT jsonb_agg(r.id) FROM public.circle_guest_rsvps r WHERE r.gathering_id=g.id AND r.attended_at IS NOT NULL),'[]'::jsonb),
  'attendees',coalesce((SELECT jsonb_agg(jsonb_build_object('personId',p.id,'fullName',concat_ws(' ',p.first_name,p.last_name),'isProspect',p.is_prospect)) FROM public.people p WHERE p.id IN(SELECT value::text::uuid FROM jsonb_array_elements_text(ids))),'[]'::jsonb),
  'notes',coalesce(c.notes,''),'finalizedAt',c.finalized_at,'editableUntil',c.editable_until,
  'canEdit',g.status<>'completed' OR (c.editable_until IS NOT NULL AND now()<c.editable_until));
END; $$;

-- Existing completed gatherings get a fixed, non-extendable correction window.
INSERT INTO public.circle_gathering_closeouts(gathering_id,organization_id,finalized_at,editable_until,finalized_by,updated_by)
SELECT g.id,g.organization_id,g.updated_at,g.updated_at+interval '7 days',g.created_by,g.created_by FROM public.circle_gatherings g
WHERE g.status='completed' ON CONFLICT DO NOTHING;

UPDATE public.organization_members om SET status='inactive'
FROM public.circle_user_links link WHERE link.user_id=om.user_id AND link.organization_id=om.organization_id
 AND link.status='active' AND om.role<>'admin';

UPDATE auth.users auth_user
SET raw_app_meta_data=coalesce(auth_user.raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('account_scope','circles')
WHERE EXISTS(SELECT 1 FROM public.circle_user_links link WHERE link.user_id=auth_user.id AND link.status='active')
  AND NOT EXISTS(SELECT 1 FROM public.organization_members om WHERE om.user_id=auth_user.id AND om.status='active' AND om.role='admin');

CREATE OR REPLACE FUNCTION public.set_circle_gathering_completion(p_gathering_id UUID,p_completed BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE g public.circle_gatherings%ROWTYPE; people_ids UUID[]; guest_ids UUID[]; closeout_notes TEXT;
BEGIN
 IF NOT p_completed THEN RAISE EXCEPTION 'Completed gatherings cannot be reopened; use closeout corrections'; END IF;
 SELECT * INTO g FROM public.circle_gatherings WHERE id=p_gathering_id;
 IF g.scope='organization' THEN
  SELECT coalesce(array_agg(r.person_id),ARRAY[]::UUID[]) INTO people_ids FROM public.circle_gathering_attendance_records r WHERE r.gathering_id=g.id AND r.person_id IS NOT NULL;
 ELSE
  SELECT coalesce(array_agg(a.person_id),ARRAY[]::UUID[]) INTO people_ids FROM public.cell_group_session_attendees a WHERE a.session_id=g.attendance_session_id;
 END IF;
 SELECT coalesce(array_agg(r.id),ARRAY[]::UUID[]) INTO guest_ids FROM public.circle_guest_rsvps r WHERE r.gathering_id=g.id AND r.attended_at IS NOT NULL;
 SELECT coalesce(c.notes,'') INTO closeout_notes FROM public.circle_gathering_closeouts c WHERE c.gathering_id=g.id;
 PERFORM public.save_circle_gathering_closeout(g.id,people_ids,guest_ids,'[]'::jsonb,coalesce(closeout_notes,''),true);
END; $$;

REVOKE ALL ON FUNCTION public.save_circle_gathering_closeout(UUID,UUID[],UUID[],JSONB,TEXT,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_circle_gathering_closeout(UUID,UUID[],UUID[],JSONB,TEXT,BOOLEAN) TO authenticated;
REVOKE ALL ON FUNCTION public.circle_has_app_access(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.circle_has_app_access(UUID) TO authenticated;
COMMIT;
