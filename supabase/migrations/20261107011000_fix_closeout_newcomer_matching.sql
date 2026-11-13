BEGIN;

-- Resolve PL/pgSQL newcomer fields as variables while keeping qualified People columns explicit.
CREATE OR REPLACE FUNCTION public.save_circle_gathering_closeout(
  p_gathering_id UUID, p_person_ids UUID[] DEFAULT ARRAY[]::UUID[],
  p_guest_rsvp_ids UUID[] DEFAULT ARRAY[]::UUID[], p_newcomers JSONB DEFAULT '[]'::jsonb,
  p_notes TEXT DEFAULT '', p_complete BOOLEAN DEFAULT false
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
#variable_conflict use_variable
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

COMMIT;
