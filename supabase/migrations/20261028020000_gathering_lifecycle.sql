BEGIN;

ALTER TABLE public.circle_gatherings
  ADD COLUMN IF NOT EXISTS ends_at TIMESTAMPTZ;

UPDATE public.circle_gatherings
SET ends_at = starts_at + INTERVAL '2 hours'
WHERE ends_at IS NULL;

ALTER TABLE public.circle_gatherings
  ALTER COLUMN ends_at SET NOT NULL;

ALTER TABLE public.circle_gatherings
  DROP CONSTRAINT IF EXISTS circle_gatherings_end_after_start;
ALTER TABLE public.circle_gatherings
  ADD CONSTRAINT circle_gatherings_end_after_start CHECK (ends_at > starts_at);

CREATE INDEX IF NOT EXISTS circle_gatherings_public_end_idx
  ON public.circle_gatherings(organization_id, ends_at)
  WHERE published_at IS NOT NULL AND status = 'scheduled';

DROP POLICY IF EXISTS "Circle members create own RSVP" ON public.circle_gathering_rsvps;
CREATE POLICY "Circle members create own RSVP" ON public.circle_gathering_rsvps
FOR INSERT TO authenticated WITH CHECK (
  person_id = public.circle_current_person_id(organization_id)
  AND EXISTS (
    SELECT 1 FROM public.circle_gatherings gathering
    WHERE gathering.id = gathering_id
      AND gathering.organization_id = circle_gathering_rsvps.organization_id
      AND gathering.status = 'scheduled'
      AND gathering.starts_at > now()
      AND public.circle_can_access_gathering(gathering.id)
  )
);

DROP POLICY IF EXISTS "Circle members update own RSVP" ON public.circle_gathering_rsvps;
CREATE POLICY "Circle members update own RSVP" ON public.circle_gathering_rsvps
FOR UPDATE TO authenticated
USING (person_id = public.circle_current_person_id(organization_id))
WITH CHECK (
  person_id = public.circle_current_person_id(organization_id)
  AND EXISTS (
    SELECT 1 FROM public.circle_gatherings gathering
    WHERE gathering.id = gathering_id
      AND gathering.organization_id = circle_gathering_rsvps.organization_id
      AND gathering.status = 'scheduled'
      AND gathering.starts_at > now()
      AND public.circle_can_access_gathering(gathering.id)
  )
);

CREATE OR REPLACE FUNCTION public.get_circle_dashboard()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_org UUID; v_person UUID; v_admin BOOLEAN; result JSONB;
BEGIN
  SELECT membership.organization_id,(membership.role='admin') INTO v_org,v_admin
  FROM public.organization_members membership WHERE membership.user_id=auth.uid() AND membership.status='active'
  ORDER BY (membership.role='admin') DESC,membership.created_at LIMIT 1;
  IF v_org IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  v_person:=public.circle_current_person_id(v_org);
  WITH accessible_groups AS (
    SELECT group_row.id,group_row.name FROM public.cell_groups group_row
    LEFT JOIN public.cell_group_members member ON member.cell_group_id=group_row.id AND member.person_id=v_person
    WHERE group_row.organization_id=v_org AND group_row.status='active'
      AND (v_admin OR member.id IS NOT NULL OR group_row.leader_person_id=v_person)
  ), meetings AS (
    SELECT gathering.*,group_row.name AS group_name,
      (v_admin OR (gathering.scope='organization' AND gathering.created_by=auth.uid()) OR (gathering.scope='circle' AND public.circle_can_lead_group(gathering.cell_group_id))) AS can_manage
    FROM public.circle_gatherings gathering LEFT JOIN public.cell_groups group_row ON group_row.id=gathering.cell_group_id
    WHERE gathering.organization_id=v_org AND gathering.assignment_confirmed_at IS NOT NULL
      AND (gathering.scope='organization' OR gathering.cell_group_id IN (SELECT id FROM accessible_groups))
  )
  SELECT jsonb_build_object(
    'meetings',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',meeting.id,'organizationId',meeting.organization_id,'groupId',meeting.cell_group_id,'scope',meeting.scope,
      'destinationName',CASE WHEN meeting.scope='organization' THEN 'Everyone' ELSE meeting.group_name END,
      'canManage',meeting.can_manage,'title',meeting.title,'meetingDate',meeting.starts_at,'endsAt',meeting.ends_at,'location',meeting.location,
      'studyTopic',meeting.study_topic,'notes',meeting.notes,'summary',meeting.summary,'status',meeting.status,
      'createdBy',meeting.created_by,'assignedLeaderId',meeting.leader_person_id,'slug',meeting.public_slug,'coverUrl',meeting.cover_url,
      'visibility',meeting.visibility,'publishedAt',meeting.published_at,'guestRsvpEnabled',meeting.guest_rsvp_enabled,
      'assignmentConfirmedAt',meeting.assignment_confirmed_at,'rsvps',COALESCE((SELECT jsonb_object_agg(rsvp.person_id::text,rsvp.status) FROM public.circle_gathering_rsvps rsvp WHERE rsvp.gathering_id=meeting.id),'{}'::jsonb)
    ) ORDER BY meeting.starts_at) FROM meetings meeting),'[]'::jsonb),
    'members',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',person.id,'personId',person.id,'fullName',concat_ws(' ',person.first_name,person.last_name),'email',person.email,'role','member'
    ) ORDER BY person.last_name,person.first_name) FROM public.people person WHERE person.organization_id=v_org AND lower(person.status)='active' AND EXISTS(
      SELECT 1 FROM public.cell_group_members member JOIN public.cell_groups group_row ON group_row.id=member.cell_group_id
      WHERE member.person_id=person.id AND group_row.organization_id=v_org AND group_row.status='active'
    )),'[]'::jsonb),
    'prayers',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',prayer.id,'groupId',prayer.cell_group_id,'destinationName',group_row.name,'userId',prayer.person_id,
      'authorName',concat_ws(' ',person.first_name,person.last_name),'title',prayer.title,'description',prayer.description,
      'category',prayer.category,'isAnswered',prayer.is_answered,'answeredNotes',prayer.answered_notes,'createdAt',prayer.created_at,
      'prayerCount',(SELECT count(*) FROM public.circle_prayer_clicks click WHERE click.prayer_id=prayer.id),
      'prayedByMe',EXISTS(SELECT 1 FROM public.circle_prayer_clicks click WHERE click.prayer_id=prayer.id AND click.person_id=v_person)
    ) ORDER BY prayer.created_at DESC) FROM public.circle_prayer_requests prayer JOIN accessible_groups group_row ON group_row.id=prayer.cell_group_id LEFT JOIN public.people person ON person.id=prayer.person_id WHERE NOT prayer.is_answered),'[]'::jsonb),
    'announcements',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',announcement.id,'organizationId',announcement.organization_id,'groupId',announcement.cell_group_id,
      'destinationName',COALESCE(group_row.name,'Everyone'),'title',announcement.title,'body',announcement.body,
      'publishedAt',announcement.published_at,'expiresAt',announcement.expires_at,'isPublic',announcement.is_public,
      'assignmentConfirmedAt',announcement.assignment_confirmed_at
    ) ORDER BY announcement.published_at DESC) FROM public.circle_announcements announcement LEFT JOIN accessible_groups group_row ON group_row.id=announcement.cell_group_id
      WHERE announcement.organization_id=v_org AND announcement.assignment_confirmed_at IS NOT NULL
        AND (announcement.cell_group_id IS NULL OR group_row.id IS NOT NULL) AND (announcement.expires_at IS NULL OR announcement.expires_at>now())),'[]'::jsonb),
    'galleries',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',gallery.id,'organizationId',gallery.organization_id,'groupId',gallery.cell_group_id,'destinationName',group_row.name,
      'slug',gallery.public_slug,'title',gallery.title,'description',gallery.description,'coverUrl',gallery.cover_url,
      'publishedAt',gallery.published_at,'assignmentConfirmedAt',gallery.assignment_confirmed_at,
      'photos',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',photo.id,'imageUrl',photo.image_url,'caption',photo.caption,'altText',photo.alt_text) ORDER BY photo.display_order) FROM public.circle_gallery_photos photo WHERE photo.gallery_id=gallery.id),'[]'::jsonb)
    ) ORDER BY gallery.published_at DESC) FROM public.circle_galleries gallery JOIN accessible_groups group_row ON group_row.id=gallery.cell_group_id
      WHERE gallery.organization_id=v_org AND gallery.status='published' AND gallery.assignment_confirmed_at IS NOT NULL),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_circle_guest_rsvp(p_gathering_id UUID,p_name TEXT,p_email TEXT,p_phone TEXT,p_status TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE gathering public.circle_gatherings%ROWTYPE; contact TEXT; rsvp_id UUID; connection_id UUID;
BEGIN
  SELECT * INTO gathering FROM public.circle_gatherings WHERE id=p_gathering_id AND visibility='public' AND published_at IS NOT NULL AND guest_rsvp_enabled AND status='scheduled' AND starts_at>now()
    AND EXISTS(SELECT 1 FROM public.circle_public_spaces space WHERE space.organization_id=circle_gatherings.organization_id AND space.is_published);
  IF gathering.id IS NULL THEN RAISE EXCEPTION 'Guest RSVP is unavailable'; END IF;
  IF nullif(trim(p_name),'') IS NULL OR p_status NOT IN('attending','tentative','declined') THEN RAISE EXCEPTION 'A valid name and response are required'; END IF;
  contact:=public.circle_normalize_guest_contact(p_email,p_phone,''); IF contact='contact:' THEN RAISE EXCEPTION 'Email or phone is required'; END IF;
  connection_id:=public.circle_upsert_guest_connection(gathering.organization_id,gathering.cell_group_id,p_name,p_email,p_phone,'','either',false,NULL);
  INSERT INTO public.circle_guest_rsvps(organization_id,gathering_id,guest_name,email,phone,normalized_contact,status,connection_id)
  VALUES(gathering.organization_id,gathering.id,trim(p_name),lower(trim(p_email)),trim(p_phone),contact,p_status,connection_id)
  ON CONFLICT(gathering_id,normalized_contact) DO UPDATE SET guest_name=excluded.guest_name,email=excluded.email,phone=excluded.phone,status=excluded.status,connection_id=excluded.connection_id,updated_at=now()
  RETURNING id INTO rsvp_id;
  RETURN jsonb_build_object('ok',true,'id',rsvp_id,'connectionId',connection_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_public_space(p_org_slug TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object(
   'organization',jsonb_build_object('id',organization.id,'slug',organization.slug,'name',organization.name,'imageUrl',organization.image,'subscriptionStatus',organization.status,'circlesEnabled',true),
   'introduction',space.introduction,'heroTitle',space.hero_title,'heroImageUrl',space.hero_image_url,
   'announcements',COALESCE((SELECT jsonb_agg(jsonb_build_object(
     'id',announcement.id,'organizationId',announcement.organization_id,'groupId',announcement.cell_group_id,
     'title',announcement.title,'body',announcement.body,'publishedAt',announcement.published_at,
     'expiresAt',announcement.expires_at,'isPublic',true
   ) ORDER BY announcement.published_at DESC) FROM public.circle_announcements announcement
     WHERE announcement.organization_id=organization.id AND announcement.is_public AND (announcement.expires_at IS NULL OR announcement.expires_at>now())),'[]'::jsonb),
   'gatherings',COALESCE((SELECT jsonb_agg(jsonb_build_object(
     'id',gathering.id,'organizationId',gathering.organization_id,'groupId',gathering.cell_group_id,'scope',gathering.scope,
     'destinationName',CASE WHEN gathering.scope='organization' THEN 'Everyone' ELSE group_row.name END,
     'slug',gathering.public_slug,'title',gathering.title,'meetingDate',gathering.starts_at,'endsAt',gathering.ends_at,'location',gathering.location,
     'studyTopic',gathering.study_topic,'notes',gathering.notes,'summary',gathering.summary,'coverUrl',gathering.cover_url,
     'status',gathering.status,'createdBy',gathering.created_by,'visibility',gathering.visibility,
     'publishedAt',gathering.published_at,'guestRsvpEnabled',gathering.guest_rsvp_enabled,'rsvps','{}'::jsonb
   ) ORDER BY gathering.starts_at) FROM public.circle_gatherings gathering LEFT JOIN public.cell_groups group_row ON group_row.id=gathering.cell_group_id
     WHERE gathering.organization_id=organization.id AND gathering.visibility='public' AND gathering.published_at IS NOT NULL
       AND gathering.status='scheduled' AND gathering.ends_at>=now()),'[]'::jsonb),
   'testimonies',COALESCE((SELECT jsonb_agg(jsonb_build_object(
     'id',testimony.id,'organizationId',testimony.organization_id,'groupId',testimony.cell_group_id,'slug',testimony.public_slug,
     'title',testimony.title,'body',testimony.body,'authorName',testimony.author_display_name,'imageUrl',testimony.image_url,'publishedAt',testimony.published_at
   ) ORDER BY testimony.published_at DESC) FROM public.circle_testimonies testimony
     WHERE testimony.organization_id=organization.id AND testimony.status='published'),'[]'::jsonb),
   'galleries',COALESCE((SELECT jsonb_agg(jsonb_build_object(
     'id',gallery.id,'organizationId',gallery.organization_id,'gatheringId',gallery.gathering_id,'groupId',gallery.cell_group_id,
     'slug',gallery.public_slug,'title',gallery.title,'description',gallery.description,'coverUrl',gallery.cover_url,'publishedAt',gallery.published_at,
     'photos',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',photo.id,'imageUrl',photo.image_url,'caption',photo.caption,'altText',photo.alt_text) ORDER BY photo.display_order)
       FROM public.circle_gallery_photos photo WHERE photo.gallery_id=gallery.id AND photo.is_published),'[]'::jsonb)
   ) ORDER BY gallery.published_at DESC) FROM public.circle_galleries gallery
     WHERE gallery.organization_id=organization.id AND gallery.status='published'),'[]'::jsonb),
   'circles',COALESCE((SELECT jsonb_agg(jsonb_build_object(
     'id',group_row.id,'organizationId',group_row.organization_id,'slug',listing.public_slug,'name',group_row.name,
     'description',COALESCE(NULLIF(listing.description,''),group_row.description),'regularSchedule','','location',group_row.location,
     'leaderId',group_row.leader_person_id,'role','member','coverUrl',listing.cover_url,'isPublic',true
   ) ORDER BY group_row.name) FROM public.circle_public_listings listing JOIN public.cell_groups group_row ON group_row.id=listing.cell_group_id
     WHERE listing.organization_id=organization.id AND listing.is_published),'[]'::jsonb)
 )
 FROM public.organizations organization JOIN public.circle_public_spaces space ON space.organization_id=organization.id AND space.is_published
 WHERE organization.slug=p_org_slug AND organization.status='active' LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_public_gathering(p_org_slug TEXT,p_gathering_slug TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object(
   'organization',jsonb_build_object('id',organization.id,'slug',organization.slug,'name',organization.name),
   'gathering',jsonb_build_object(
     'id',gathering.id,'organizationId',gathering.organization_id,'groupId',gathering.cell_group_id,'scope',gathering.scope,
     'destinationName',CASE WHEN gathering.scope='organization' THEN 'Everyone' ELSE group_row.name END,
     'slug',gathering.public_slug,'title',gathering.title,'meetingDate',gathering.starts_at,'endsAt',gathering.ends_at,'location',gathering.location,
     'studyTopic',gathering.study_topic,'notes',gathering.notes,'summary',gathering.summary,'coverUrl',gathering.cover_url,
     'status',gathering.status,'createdBy',gathering.created_by,'visibility',gathering.visibility,
     'publishedAt',gathering.published_at,'guestRsvpEnabled',gathering.guest_rsvp_enabled,'rsvps','{}'::jsonb
   )
 )
 FROM public.organizations organization
 JOIN public.circle_public_spaces space ON space.organization_id=organization.id AND space.is_published
 JOIN public.circle_gatherings gathering ON gathering.organization_id=organization.id
 LEFT JOIN public.cell_groups group_row ON group_row.id=gathering.cell_group_id
 WHERE organization.slug=p_org_slug AND organization.status='active' AND gathering.public_slug=p_gathering_slug
   AND gathering.visibility='public' AND gathering.published_at IS NOT NULL AND gathering.status='scheduled' LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.stage_circle_walk_in(p_gathering_id UUID,p_name TEXT,p_email TEXT,p_phone TEXT,p_preferred_contact TEXT,p_consent BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE gathering public.circle_gatherings%ROWTYPE; connection_id UUID; rsvp_id UUID; contact_key TEXT;
BEGIN
  SELECT * INTO gathering FROM public.circle_gatherings WHERE id=p_gathering_id;
  IF gathering.id IS NULL OR NOT public.circle_can_manage_gathering(gathering.id) THEN RAISE EXCEPTION 'Gathering manager access required'; END IF;
  IF gathering.status <> 'scheduled' OR gathering.starts_at > now() THEN RAISE EXCEPTION 'Attendance is unavailable before the gathering begins or after it is completed'; END IF;
  IF nullif(trim(p_name),'') IS NULL THEN RAISE EXCEPTION 'Guest name is required'; END IF;
  contact_key:=public.circle_normalize_guest_contact(p_email,p_phone,''); IF contact_key='contact:' THEN RAISE EXCEPTION 'Email or phone is required'; END IF;
  connection_id:=public.circle_upsert_guest_connection(gathering.organization_id,gathering.cell_group_id,p_name,p_email,p_phone,'',p_preferred_contact,p_consent,CASE WHEN p_consent THEN now() ELSE NULL END);
  INSERT INTO public.circle_guest_rsvps(organization_id,gathering_id,guest_name,email,phone,normalized_contact,status,attended_at,connection_id)
  VALUES(gathering.organization_id,gathering.id,trim(p_name),lower(trim(p_email)),trim(p_phone),contact_key,'attending',now(),connection_id)
  ON CONFLICT(gathering_id,normalized_contact) DO UPDATE SET guest_name=excluded.guest_name,email=excluded.email,phone=excluded.phone,status='attending',attended_at=now(),connection_id=excluded.connection_id,updated_at=now()
  RETURNING id INTO rsvp_id;
  UPDATE public.circle_guest_connections SET status=CASE WHEN status IN('new','contacted') THEN 'visited' ELSE status END,last_activity_at=now(),updated_at=now() WHERE id=connection_id;
  RETURN jsonb_build_object('ok',true,'guestRsvpId',rsvp_id,'connectionId',connection_id);
END;
$$;

-- Retain the current attendance implementation and add lifecycle guards before
-- its existing roster validation and persistence work.
CREATE OR REPLACE FUNCTION public.record_circle_attendance(
  p_gathering_id UUID,
  p_person_ids UUID[],
  p_guest_rsvp_ids UUID[] DEFAULT ARRAY[]::UUID[]
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  gathering public.circle_gatherings%ROWTYPE;
  group_row public.cell_groups%ROWTYPE;
  v_session_id UUID;
  leader_name TEXT;
  record_id UUID;
BEGIN
  SELECT * INTO gathering FROM public.circle_gatherings WHERE id=p_gathering_id;
  IF gathering.id IS NULL OR NOT public.circle_can_manage_gathering(gathering.id) THEN RAISE EXCEPTION 'Gathering manager access required'; END IF;
  IF gathering.status <> 'scheduled' OR gathering.starts_at > now() THEN RAISE EXCEPTION 'Attendance is unavailable before the gathering begins or after it is completed'; END IF;

  IF gathering.scope='organization' THEN
    IF EXISTS(
      SELECT 1 FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id
      WHERE NOT EXISTS(
        SELECT 1 FROM public.people person
        WHERE person.id=attendee_person_id AND person.organization_id=gathering.organization_id AND lower(person.status)='active'
          AND EXISTS(SELECT 1 FROM public.cell_group_members membership JOIN public.cell_groups group_check ON group_check.id=membership.cell_group_id WHERE membership.person_id=person.id AND group_check.organization_id=gathering.organization_id AND group_check.status='active')
      )
    ) THEN RAISE EXCEPTION 'Organization event attendees must be active Circle members'; END IF;
    DELETE FROM public.circle_gathering_attendance_records WHERE gathering_id=gathering.id;
    INSERT INTO public.circle_gathering_attendance_records(organization_id,gathering_id,person_id,recorded_by)
      SELECT gathering.organization_id,gathering.id,attendee_person_id,auth.uid() FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id;
    INSERT INTO public.circle_gathering_attendance_records(organization_id,gathering_id,guest_rsvp_id,recorded_by)
      SELECT gathering.organization_id,gathering.id,rsvp_id,auth.uid() FROM unnest(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[])) rsvp_id
      WHERE EXISTS(SELECT 1 FROM public.circle_guest_rsvps rsvp WHERE rsvp.id=rsvp_id AND rsvp.gathering_id=gathering.id);
    UPDATE public.circle_guest_rsvps SET attended_at=CASE WHEN id=ANY(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[])) THEN COALESCE(attended_at,now()) ELSE NULL END,updated_at=now() WHERE gathering_id=gathering.id;
    UPDATE public.circle_gatherings SET attendance_saved_at=now(),updated_at=now() WHERE id=gathering.id;
    SELECT id INTO record_id FROM public.circle_gathering_attendance_records WHERE gathering_id=gathering.id ORDER BY created_at LIMIT 1;
    RETURN COALESCE(record_id,gathering.id);
  END IF;

  IF EXISTS(SELECT 1 FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id WHERE NOT EXISTS(SELECT 1 FROM public.people person WHERE person.id=attendee_person_id AND person.organization_id=gathering.organization_id)) THEN RAISE EXCEPTION 'An attendee is outside this organization'; END IF;
  SELECT * INTO group_row FROM public.cell_groups WHERE id=gathering.cell_group_id;
  SELECT concat_ws(' ',person.first_name,person.last_name) INTO leader_name FROM public.people person WHERE person.id=COALESCE(gathering.leader_person_id,group_row.leader_person_id);
  leader_name:=COALESCE(nullif(leader_name,''),'Circle leader');
  INSERT INTO public.cell_group_sessions(organization_id,cell_group_id,session_date,leader_person_id,leader_name,location)
  VALUES(gathering.organization_id,gathering.cell_group_id,(gathering.starts_at AT TIME ZONE 'UTC')::date,COALESCE(gathering.leader_person_id,group_row.leader_person_id),leader_name,gathering.location)
  ON CONFLICT(cell_group_id,session_date) DO UPDATE SET leader_person_id=excluded.leader_person_id,leader_name=excluded.leader_name,location=excluded.location,updated_at=now() RETURNING id INTO v_session_id;
  DELETE FROM public.cell_group_session_attendees attendee WHERE attendee.session_id=v_session_id;
  INSERT INTO public.cell_group_session_attendees(session_id,person_id) SELECT v_session_id,attendee_person_id FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id ON CONFLICT(session_id,person_id) DO NOTHING;
  UPDATE public.circle_guest_rsvps SET attended_at=CASE WHEN id=ANY(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[])) THEN COALESCE(attended_at,now()) ELSE NULL END,updated_at=now() WHERE gathering_id=gathering.id;
  UPDATE public.circle_gatherings SET attendance_session_id=v_session_id,attendance_saved_at=now(),updated_at=now() WHERE id=gathering.id;
  RETURN v_session_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_circle_gathering_completion(p_gathering_id UUID,p_completed BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE gathering public.circle_gatherings%ROWTYPE;
BEGIN
  SELECT * INTO gathering FROM public.circle_gatherings WHERE id=p_gathering_id;
  IF gathering.id IS NULL OR NOT public.circle_can_manage_gathering(gathering.id) THEN RAISE EXCEPTION 'Gathering manager access required'; END IF;
  IF gathering.status='cancelled' THEN RAISE EXCEPTION 'A cancelled gathering cannot be completed or reopened'; END IF;
  IF p_completed AND gathering.ends_at>=now() THEN RAISE EXCEPTION 'A gathering cannot be completed before it ends'; END IF;
  IF p_completed AND gathering.attendance_saved_at IS NULL THEN RAISE EXCEPTION 'Save attendance before completing the gathering'; END IF;
  UPDATE public.circle_gatherings SET status=CASE WHEN p_completed THEN 'completed' ELSE 'scheduled' END,updated_at=now() WHERE id=gathering.id;
END;
$$;

COMMIT;
