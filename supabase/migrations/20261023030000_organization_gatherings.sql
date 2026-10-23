BEGIN;

ALTER TABLE public.circle_gatherings
  ADD COLUMN IF NOT EXISTS scope TEXT NOT NULL DEFAULT 'circle';

UPDATE public.circle_gatherings SET scope = 'circle' WHERE scope IS NULL;
ALTER TABLE public.circle_gatherings ALTER COLUMN cell_group_id DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'circle_gatherings_scope_destination_check'
  ) THEN
    ALTER TABLE public.circle_gatherings
      ADD CONSTRAINT circle_gatherings_scope_destination_check CHECK (
        (scope = 'circle' AND cell_group_id IS NOT NULL) OR
        (scope = 'organization' AND cell_group_id IS NULL)
      );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.circle_can_lead_organization(p_organization_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.circle_is_org_admin(p_organization_id) OR EXISTS (
    SELECT 1
    FROM public.circle_user_links link
    JOIN public.cell_group_members membership ON membership.person_id = link.person_id
    JOIN public.cell_groups group_row ON group_row.id = membership.cell_group_id
    WHERE link.user_id = auth.uid()
      AND link.organization_id = p_organization_id
      AND link.status = 'active'
      AND group_row.organization_id = p_organization_id
      AND group_row.status = 'active'
      AND (membership.role = 'Leader' OR group_row.leader_person_id = link.person_id)
  );
$$;

CREATE OR REPLACE FUNCTION public.circle_can_access_gathering(p_gathering_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.circle_gatherings gathering
    WHERE gathering.id = p_gathering_id AND (
      (gathering.scope = 'circle' AND public.circle_can_access_group(gathering.cell_group_id)) OR
      (gathering.scope = 'organization' AND EXISTS (
        SELECT 1 FROM public.organization_members membership
        WHERE membership.organization_id = gathering.organization_id
          AND membership.user_id = auth.uid() AND membership.status = 'active'
      ))
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.circle_can_manage_gathering(p_gathering_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.circle_gatherings gathering
    WHERE gathering.id = p_gathering_id AND (
      public.circle_is_org_admin(gathering.organization_id) OR
      (gathering.scope = 'circle' AND public.circle_can_lead_group(gathering.cell_group_id)) OR
      (gathering.scope = 'organization' AND gathering.created_by = auth.uid())
    )
  );
$$;

DROP POLICY IF EXISTS "Circle leaders create gatherings" ON public.circle_gatherings;
CREATE POLICY "Circle leaders create gatherings" ON public.circle_gatherings
FOR INSERT TO authenticated WITH CHECK (
  created_by = auth.uid() AND (
    (scope = 'circle' AND public.circle_can_lead_group(cell_group_id) AND EXISTS (
      SELECT 1 FROM public.cell_groups group_row
      WHERE group_row.id = cell_group_id AND group_row.organization_id = circle_gatherings.organization_id
    )) OR
    (scope = 'organization' AND cell_group_id IS NULL AND public.circle_can_lead_organization(organization_id))
  )
);

DROP POLICY IF EXISTS "Circle leaders update gatherings" ON public.circle_gatherings;
CREATE POLICY "Circle leaders update gatherings" ON public.circle_gatherings
FOR UPDATE TO authenticated
USING (public.circle_can_manage_gathering(id))
WITH CHECK (
  public.circle_can_manage_gathering(id) AND (
    (scope = 'circle' AND cell_group_id IS NOT NULL) OR
    (scope = 'organization' AND cell_group_id IS NULL)
  )
);

DROP POLICY IF EXISTS "Circle members create own RSVP" ON public.circle_gathering_rsvps;
CREATE POLICY "Circle members create own RSVP" ON public.circle_gathering_rsvps
FOR INSERT TO authenticated WITH CHECK (
  person_id = public.circle_current_person_id(organization_id)
  AND EXISTS (
    SELECT 1 FROM public.circle_gatherings gathering
    WHERE gathering.id = gathering_id
      AND gathering.organization_id = circle_gathering_rsvps.organization_id
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
      AND public.circle_can_access_gathering(gathering.id)
  )
);

CREATE TABLE IF NOT EXISTS public.circle_gathering_attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  gathering_id UUID NOT NULL REFERENCES public.circle_gatherings(id) ON DELETE CASCADE,
  person_id UUID REFERENCES public.people(id) ON DELETE CASCADE,
  guest_rsvp_id UUID REFERENCES public.circle_guest_rsvps(id) ON DELETE CASCADE,
  attended_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  recorded_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((person_id IS NOT NULL)::int + (guest_rsvp_id IS NOT NULL)::int = 1)
);
CREATE UNIQUE INDEX IF NOT EXISTS circle_gathering_attendance_person_idx
  ON public.circle_gathering_attendance_records(gathering_id, person_id) WHERE person_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS circle_gathering_attendance_guest_idx
  ON public.circle_gathering_attendance_records(gathering_id, guest_rsvp_id) WHERE guest_rsvp_id IS NOT NULL;
ALTER TABLE public.circle_gathering_attendance_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Gathering managers read organization attendance" ON public.circle_gathering_attendance_records;
CREATE POLICY "Gathering managers read organization attendance"
ON public.circle_gathering_attendance_records FOR SELECT TO authenticated
USING (public.circle_can_manage_gathering(gathering_id));

ALTER TABLE public.circle_guest_connections ALTER COLUMN cell_group_id DROP NOT NULL;
ALTER TABLE public.circle_guest_connections DROP CONSTRAINT IF EXISTS circle_guest_connections_organization_id_cell_group_id_normalized_contact_key;
CREATE UNIQUE INDEX IF NOT EXISTS circle_guest_connections_assigned_contact_idx
  ON public.circle_guest_connections(organization_id, cell_group_id, normalized_contact)
  WHERE cell_group_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS circle_guest_connections_unassigned_contact_idx
  ON public.circle_guest_connections(organization_id, normalized_contact)
  WHERE cell_group_id IS NULL;

CREATE OR REPLACE FUNCTION public.circle_upsert_guest_connection(
  p_organization_id UUID,p_cell_group_id UUID,p_name TEXT,p_email TEXT,p_phone TEXT,
  p_fallback_contact TEXT,p_preferred_contact TEXT,p_opt_in BOOLEAN,p_consented_at TIMESTAMPTZ DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE contact_key TEXT; connection_id UUID;
BEGIN
  contact_key := public.circle_normalize_guest_contact(p_email,p_phone,p_fallback_contact);
  IF contact_key='contact:' THEN RAISE EXCEPTION 'Email or phone is required'; END IF;
  IF p_cell_group_id IS NULL THEN
    INSERT INTO public.circle_guest_connections(
      organization_id,cell_group_id,normalized_contact,guest_name,email,phone,
      preferred_contact,follow_up_opt_in,consented_at,last_activity_at
    ) VALUES(
      p_organization_id,NULL,contact_key,trim(p_name),lower(trim(COALESCE(p_email,''))),trim(COALESCE(p_phone,'')),
      CASE WHEN p_preferred_contact IN ('email','phone','either') THEN p_preferred_contact ELSE 'either' END,
      COALESCE(p_opt_in,false),CASE WHEN p_opt_in THEN COALESCE(p_consented_at,now()) ELSE NULL END,now()
    ) ON CONFLICT (organization_id, normalized_contact) WHERE cell_group_id IS NULL DO UPDATE SET
      guest_name=excluded.guest_name,
      email=CASE WHEN excluded.email<>'' THEN excluded.email ELSE circle_guest_connections.email END,
      phone=CASE WHEN excluded.phone<>'' THEN excluded.phone ELSE circle_guest_connections.phone END,
      preferred_contact=CASE WHEN excluded.follow_up_opt_in THEN excluded.preferred_contact ELSE circle_guest_connections.preferred_contact END,
      follow_up_opt_in=circle_guest_connections.follow_up_opt_in OR excluded.follow_up_opt_in,
      consented_at=COALESCE(circle_guest_connections.consented_at,excluded.consented_at),
      status=CASE WHEN circle_guest_connections.status='closed' AND excluded.follow_up_opt_in THEN 'new' ELSE circle_guest_connections.status END,
      last_activity_at=now(),updated_at=now()
    RETURNING id INTO connection_id;
  ELSE
    INSERT INTO public.circle_guest_connections(
      organization_id,cell_group_id,normalized_contact,guest_name,email,phone,
      preferred_contact,follow_up_opt_in,consented_at,last_activity_at
    ) VALUES(
      p_organization_id,p_cell_group_id,contact_key,trim(p_name),lower(trim(COALESCE(p_email,''))),trim(COALESCE(p_phone,'')),
      CASE WHEN p_preferred_contact IN ('email','phone','either') THEN p_preferred_contact ELSE 'either' END,
      COALESCE(p_opt_in,false),CASE WHEN p_opt_in THEN COALESCE(p_consented_at,now()) ELSE NULL END,now()
    ) ON CONFLICT (organization_id, cell_group_id, normalized_contact) WHERE cell_group_id IS NOT NULL DO UPDATE SET
      guest_name=excluded.guest_name,
      email=CASE WHEN excluded.email<>'' THEN excluded.email ELSE circle_guest_connections.email END,
      phone=CASE WHEN excluded.phone<>'' THEN excluded.phone ELSE circle_guest_connections.phone END,
      preferred_contact=CASE WHEN excluded.follow_up_opt_in THEN excluded.preferred_contact ELSE circle_guest_connections.preferred_contact END,
      follow_up_opt_in=circle_guest_connections.follow_up_opt_in OR excluded.follow_up_opt_in,
      consented_at=COALESCE(circle_guest_connections.consented_at,excluded.consented_at),
      status=CASE WHEN circle_guest_connections.status='closed' AND excluded.follow_up_opt_in THEN 'new' ELSE circle_guest_connections.status END,
      last_activity_at=now(),updated_at=now()
    RETURNING id INTO connection_id;
  END IF;
  RETURN connection_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.circle_content_assignment_guard()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_type TEXT := CASE TG_TABLE_NAME WHEN 'circle_gatherings' THEN 'gathering' WHEN 'circle_galleries' THEN 'gallery' WHEN 'circle_testimonies' THEN 'testimony' WHEN 'circle_announcements' THEN 'announcement' END;
  v_group_org UUID;
  v_scope TEXT := COALESCE(to_jsonb(NEW)->>'scope', CASE WHEN NEW.cell_group_id IS NULL THEN 'organization' ELSE 'circle' END);
BEGIN
  IF NEW.cell_group_id IS NULL AND v_type NOT IN ('announcement','gathering') THEN RAISE EXCEPTION 'A Circle assignment is required'; END IF;
  IF v_type = 'gathering' AND ((v_scope = 'circle' AND NEW.cell_group_id IS NULL) OR (v_scope = 'organization' AND NEW.cell_group_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'The gathering destination does not match its scope';
  END IF;
  IF NEW.cell_group_id IS NULL AND v_type = 'announcement' AND NOT public.circle_is_org_admin(NEW.organization_id) THEN
    RAISE EXCEPTION 'Only organization administrators can publish organization-wide announcements';
  END IF;
  IF NEW.cell_group_id IS NOT NULL THEN
    SELECT organization_id INTO v_group_org FROM public.cell_groups WHERE id=NEW.cell_group_id AND status='active';
    IF v_group_org IS NULL OR v_group_org<>NEW.organization_id THEN RAISE EXCEPTION 'The content destination must be an active Circle in the same organization'; END IF;
  END IF;
  IF TG_OP='INSERT' THEN
    NEW.assignment_confirmed_at:=COALESCE(NEW.assignment_confirmed_at,now()); NEW.assignment_confirmed_by:=COALESCE(NEW.assignment_confirmed_by,auth.uid()); RETURN NEW;
  END IF;
  IF NEW.cell_group_id IS DISTINCT FROM OLD.cell_group_id THEN
    IF NOT public.circle_is_org_admin(NEW.organization_id) THEN RAISE EXCEPTION 'Only organization administrators can reassign existing content'; END IF;
    NEW.assignment_confirmed_at:=now(); NEW.assignment_confirmed_by:=auth.uid();
    INSERT INTO public.circle_content_assignment_audit(organization_id,content_type,content_id,previous_cell_group_id,next_cell_group_id,action,performed_by)
    VALUES(NEW.organization_id,v_type,NEW.id,OLD.cell_group_id,NEW.cell_group_id,'reassigned',auth.uid());
  ELSIF OLD.assignment_confirmed_at IS NULL AND NEW.assignment_confirmed_at IS NOT NULL THEN
    IF NOT public.circle_is_org_admin(NEW.organization_id) THEN RAISE EXCEPTION 'Only organization administrators can confirm legacy content assignments'; END IF;
    NEW.assignment_confirmed_at:=now(); NEW.assignment_confirmed_by:=auth.uid();
    INSERT INTO public.circle_content_assignment_audit(organization_id,content_type,content_id,previous_cell_group_id,next_cell_group_id,action,performed_by)
    VALUES(NEW.organization_id,v_type,NEW.id,OLD.cell_group_id,NEW.cell_group_id,'confirmed',auth.uid());
  ELSIF OLD.assignment_confirmed_at IS NOT NULL AND NEW.assignment_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'A confirmed content assignment cannot be returned to review';
  ELSE NEW.assignment_confirmed_at:=OLD.assignment_confirmed_at; NEW.assignment_confirmed_by:=OLD.assignment_confirmed_by;
  END IF;
  RETURN NEW;
END;
$$;

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
      'canManage',meeting.can_manage,'title',meeting.title,'meetingDate',meeting.starts_at,'location',meeting.location,
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
  SELECT * INTO gathering FROM public.circle_gatherings WHERE id=p_gathering_id AND visibility='public' AND published_at IS NOT NULL AND guest_rsvp_enabled AND status='scheduled' AND starts_at>=now()
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
     'slug',gathering.public_slug,'title',gathering.title,'meetingDate',gathering.starts_at,'location',gathering.location,
     'studyTopic',gathering.study_topic,'notes',gathering.notes,'summary',gathering.summary,'coverUrl',gathering.cover_url,
     'status',gathering.status,'createdBy',gathering.created_by,'visibility',gathering.visibility,
     'publishedAt',gathering.published_at,'guestRsvpEnabled',gathering.guest_rsvp_enabled,'rsvps','{}'::jsonb
   ) ORDER BY gathering.starts_at) FROM public.circle_gatherings gathering LEFT JOIN public.cell_groups group_row ON group_row.id=gathering.cell_group_id
     WHERE gathering.organization_id=organization.id AND gathering.visibility='public' AND gathering.published_at IS NOT NULL
       AND gathering.status='scheduled' AND gathering.starts_at>=now()),'[]'::jsonb),
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
     'slug',gathering.public_slug,'title',gathering.title,'meetingDate',gathering.starts_at,'location',gathering.location,
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

CREATE OR REPLACE FUNCTION public.record_circle_attendance(p_gathering_id UUID,p_person_ids UUID[],p_guest_rsvp_ids UUID[] DEFAULT ARRAY[]::UUID[])
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE gathering public.circle_gatherings%ROWTYPE; group_row public.cell_groups%ROWTYPE; v_session_id UUID; leader_name TEXT; record_id UUID;
BEGIN
  SELECT * INTO gathering FROM public.circle_gatherings WHERE id=p_gathering_id;
  IF gathering.id IS NULL OR NOT public.circle_can_manage_gathering(gathering.id) THEN RAISE EXCEPTION 'Gathering manager access required'; END IF;
  IF gathering.scope='organization' THEN
    IF EXISTS(SELECT 1 FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id WHERE NOT EXISTS(
      SELECT 1 FROM public.people person WHERE person.id=attendee_person_id AND person.organization_id=gathering.organization_id AND lower(person.status)='active' AND EXISTS(
        SELECT 1 FROM public.cell_group_members membership JOIN public.cell_groups group_check ON group_check.id=membership.cell_group_id
        WHERE membership.person_id=person.id AND group_check.organization_id=gathering.organization_id AND group_check.status='active'
      )
    )) THEN RAISE EXCEPTION 'Organization event attendees must be active Circle members'; END IF;
    DELETE FROM public.circle_gathering_attendance_records WHERE gathering_id=gathering.id;
    INSERT INTO public.circle_gathering_attendance_records(organization_id,gathering_id,person_id,recorded_by)
      SELECT gathering.organization_id,gathering.id,attendee_person_id,auth.uid() FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id;
    INSERT INTO public.circle_gathering_attendance_records(organization_id,gathering_id,guest_rsvp_id,recorded_by)
      SELECT gathering.organization_id,gathering.id,rsvp_id,auth.uid() FROM unnest(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[])) rsvp_id
      WHERE EXISTS(SELECT 1 FROM public.circle_guest_rsvps rsvp WHERE rsvp.id=rsvp_id AND rsvp.gathering_id=gathering.id);
    UPDATE public.circle_guest_rsvps SET attended_at=now(),updated_at=now() WHERE gathering_id=gathering.id AND id=ANY(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[]));
    UPDATE public.circle_gatherings SET status='completed',updated_at=now() WHERE id=gathering.id;
    SELECT id INTO record_id FROM public.circle_gathering_attendance_records WHERE gathering_id=gathering.id ORDER BY created_at LIMIT 1;
    RETURN COALESCE(record_id,gathering.id);
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id WHERE NOT EXISTS(
    SELECT 1 FROM public.people person WHERE person.id=attendee_person_id AND person.organization_id=gathering.organization_id
  )) THEN RAISE EXCEPTION 'An attendee is outside this organization'; END IF;
  SELECT * INTO group_row FROM public.cell_groups WHERE id=gathering.cell_group_id;
  SELECT concat_ws(' ',person.first_name,person.last_name) INTO leader_name FROM public.people person WHERE person.id=COALESCE(gathering.leader_person_id,group_row.leader_person_id);
  leader_name:=COALESCE(nullif(leader_name,''),'Circle leader');
  INSERT INTO public.cell_group_sessions(organization_id,cell_group_id,session_date,leader_person_id,leader_name,location)
  VALUES(gathering.organization_id,gathering.cell_group_id,(gathering.starts_at AT TIME ZONE 'UTC')::date,COALESCE(gathering.leader_person_id,group_row.leader_person_id),leader_name,gathering.location)
  ON CONFLICT(cell_group_id,session_date) DO UPDATE SET leader_person_id=excluded.leader_person_id,leader_name=excluded.leader_name,location=excluded.location,updated_at=now() RETURNING id INTO v_session_id;
  DELETE FROM public.cell_group_session_attendees attendee WHERE attendee.session_id=v_session_id;
  INSERT INTO public.cell_group_session_attendees(session_id,person_id) SELECT v_session_id,attendee_person_id FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id ON CONFLICT(session_id,person_id) DO NOTHING;
  UPDATE public.circle_guest_rsvps SET attended_at=now(),updated_at=now() WHERE gathering_id=gathering.id AND id=ANY(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[]));
  UPDATE public.circle_gatherings SET attendance_session_id=v_session_id,status='completed',updated_at=now() WHERE id=gathering.id;
  RETURN v_session_id;
END;
$$;

DROP POLICY IF EXISTS "Leaders read guest connections" ON public.circle_guest_connections;
CREATE POLICY "Leaders read guest connections" ON public.circle_guest_connections FOR SELECT TO authenticated
USING (
  public.circle_is_org_admin(organization_id) OR
  (cell_group_id IS NULL AND public.circle_can_lead_organization(organization_id)) OR
  (cell_group_id IS NOT NULL AND public.circle_can_lead_group(cell_group_id))
);
DROP POLICY IF EXISTS "Leaders read guest connection activities" ON public.circle_guest_connection_activities;
CREATE POLICY "Leaders read guest connection activities" ON public.circle_guest_connection_activities FOR SELECT TO authenticated
USING (EXISTS(
  SELECT 1 FROM public.circle_guest_connections connection
  WHERE connection.id=connection_id AND (
    public.circle_is_org_admin(connection.organization_id) OR
    (connection.cell_group_id IS NULL AND public.circle_can_lead_organization(connection.organization_id)) OR
    (connection.cell_group_id IS NOT NULL AND public.circle_can_lead_group(connection.cell_group_id))
  )
));

CREATE OR REPLACE FUNCTION public.get_circle_connections(p_cell_group_id UUID DEFAULT NULL,p_filter TEXT DEFAULT 'active')
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',connection.id,'organizationId',connection.organization_id,'groupId',connection.cell_group_id,'groupName',COALESCE(group_row.name,'Unassigned'),
    'name',connection.guest_name,'email',connection.email,'phone',connection.phone,'preferredContact',connection.preferred_contact,
    'followUpOptIn',connection.follow_up_opt_in,'consentedAt',connection.consented_at,'status',connection.status,
    'claimedByPersonId',connection.claimed_by_person_id,'claimedByName',concat_ws(' ',person.first_name,person.last_name),
    'convertedPersonId',connection.converted_person_id,'lastActivityAt',connection.last_activity_at,
    'rsvpCount',(SELECT count(*) FROM public.circle_guest_rsvps rsvp WHERE rsvp.connection_id=connection.id),
    'interestCount',(SELECT count(*) FROM public.circle_join_interests interest WHERE interest.connection_id=connection.id),
    'attended',EXISTS(SELECT 1 FROM public.circle_guest_rsvps rsvp WHERE rsvp.connection_id=connection.id AND rsvp.attended_at IS NOT NULL)
  ) ORDER BY connection.last_activity_at DESC),'[]'::jsonb)
  FROM public.circle_guest_connections connection
  LEFT JOIN public.cell_groups group_row ON group_row.id=connection.cell_group_id
  LEFT JOIN public.people person ON person.id=connection.claimed_by_person_id
  WHERE (p_cell_group_id IS NULL OR connection.cell_group_id=p_cell_group_id)
    AND (
      public.circle_is_org_admin(connection.organization_id) OR
      (connection.cell_group_id IS NULL AND public.circle_can_lead_organization(connection.organization_id)) OR
      (connection.cell_group_id IS NOT NULL AND public.circle_can_lead_group(connection.cell_group_id))
    )
    AND CASE p_filter
      WHEN 'attention' THEN connection.follow_up_opt_in AND connection.status='new'
      WHEN 'active' THEN connection.status IN ('new','contacted','visited')
      WHEN 'connected' THEN connection.status='connected'
      WHEN 'closed' THEN connection.status='closed'
      ELSE true END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_connection(p_connection_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE connection public.circle_guest_connections%ROWTYPE; result JSONB;
BEGIN
  SELECT * INTO connection FROM public.circle_guest_connections WHERE id=p_connection_id;
  IF connection.id IS NULL OR NOT (
    public.circle_is_org_admin(connection.organization_id) OR
    (connection.cell_group_id IS NULL AND public.circle_can_lead_organization(connection.organization_id)) OR
    (connection.cell_group_id IS NOT NULL AND public.circle_can_lead_group(connection.cell_group_id))
  ) THEN RAISE EXCEPTION 'Connection not available'; END IF;
  SELECT jsonb_build_object(
    'id',connection.id,'organizationId',connection.organization_id,'groupId',connection.cell_group_id,'groupName',COALESCE(group_row.name,'Unassigned'),
    'name',connection.guest_name,'email',connection.email,'phone',connection.phone,'preferredContact',connection.preferred_contact,
    'followUpOptIn',connection.follow_up_opt_in,'consentedAt',connection.consented_at,'status',connection.status,
    'claimedByPersonId',connection.claimed_by_person_id,'claimedByName',concat_ws(' ',person.first_name,person.last_name),
    'convertedPersonId',connection.converted_person_id,'lastActivityAt',connection.last_activity_at,
    'rsvps',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',rsvp.id,'gatheringId',rsvp.gathering_id,'title',gathering.title,'startsAt',gathering.starts_at,'status',rsvp.status,'attendedAt',rsvp.attended_at) ORDER BY gathering.starts_at DESC) FROM public.circle_guest_rsvps rsvp JOIN public.circle_gatherings gathering ON gathering.id=rsvp.gathering_id WHERE rsvp.connection_id=connection.id),'[]'::jsonb),
    'interests',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',interest.id,'message',interest.message,'status',interest.status,'createdAt',interest.created_at) ORDER BY interest.created_at DESC) FROM public.circle_join_interests interest WHERE interest.connection_id=connection.id),'[]'::jsonb),
    'activities',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',activity.id,'type',activity.activity_type,'body',activity.body,'createdAt',activity.created_at) ORDER BY activity.created_at DESC) FROM public.circle_guest_connection_activities activity WHERE activity.connection_id=connection.id),'[]'::jsonb)
  ) INTO result
  FROM (SELECT 1) seed
  LEFT JOIN public.cell_groups group_row ON group_row.id=connection.cell_group_id
  LEFT JOIN public.people person ON person.id=connection.claimed_by_person_id;
  RETURN result;
END;
$$;

DROP FUNCTION IF EXISTS public.update_circle_connection(UUID,TEXT,TEXT);
CREATE FUNCTION public.update_circle_connection(p_connection_id UUID,p_action TEXT,p_note TEXT DEFAULT '',p_cell_group_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE connection public.circle_guest_connections%ROWTYPE; current_person UUID; next_status TEXT; activity TEXT; target_group UUID;
BEGIN
  SELECT * INTO connection FROM public.circle_guest_connections WHERE id=p_connection_id FOR UPDATE;
  IF connection.id IS NULL OR NOT (
    public.circle_is_org_admin(connection.organization_id) OR
    (connection.cell_group_id IS NULL AND public.circle_can_lead_organization(connection.organization_id)) OR
    (connection.cell_group_id IS NOT NULL AND public.circle_can_lead_group(connection.cell_group_id))
  ) THEN RAISE EXCEPTION 'Leader access required'; END IF;
  current_person:=public.circle_current_person_id(connection.organization_id);
  IF p_action='claim' THEN
    target_group:=COALESCE(connection.cell_group_id,p_cell_group_id);
    IF target_group IS NULL THEN RAISE EXCEPTION 'Choose a Circle before claiming this guest'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.cell_groups group_row WHERE group_row.id=target_group AND group_row.organization_id=connection.organization_id AND group_row.status='active') THEN RAISE EXCEPTION 'Choose an active Circle in this organization'; END IF;
    IF NOT (public.circle_is_org_admin(connection.organization_id) OR public.circle_can_lead_group(target_group)) THEN RAISE EXCEPTION 'You can assign guests only to Circles you manage'; END IF;
    IF current_person IS NULL THEN RAISE EXCEPTION 'A linked People record is required to claim follow-up'; END IF;
    UPDATE public.circle_guest_connections SET cell_group_id=target_group,claimed_by_person_id=current_person,updated_at=now() WHERE id=connection.id; activity:='claimed';
  ELSIF p_action='unclaim' THEN
    UPDATE public.circle_guest_connections SET claimed_by_person_id=NULL,updated_at=now() WHERE id=connection.id; activity:='unclaimed';
  ELSIF p_action='contacted' THEN
    next_status:=CASE WHEN connection.status='new' THEN 'contacted' ELSE connection.status END;
    UPDATE public.circle_guest_connections SET status=next_status,last_activity_at=now(),updated_at=now() WHERE id=connection.id; activity:='contacted';
  ELSIF p_action='close' THEN
    UPDATE public.circle_guest_connections SET status='closed',last_activity_at=now(),updated_at=now() WHERE id=connection.id; activity:='status_changed';
  ELSIF p_action='reopen' THEN
    next_status:=CASE WHEN EXISTS(SELECT 1 FROM public.circle_guest_rsvps rsvp WHERE rsvp.connection_id=connection.id AND rsvp.attended_at IS NOT NULL) THEN 'visited' ELSE 'new' END;
    UPDATE public.circle_guest_connections SET status=next_status,last_activity_at=now(),updated_at=now() WHERE id=connection.id; activity:='status_changed';
  ELSIF p_action='note' THEN
    IF nullif(trim(p_note),'') IS NULL THEN RAISE EXCEPTION 'Note cannot be empty'; END IF; activity:='note';
    UPDATE public.circle_guest_connections SET last_activity_at=now(),updated_at=now() WHERE id=connection.id;
  ELSE RAISE EXCEPTION 'Unsupported connection action'; END IF;
  INSERT INTO public.circle_guest_connection_activities(organization_id,connection_id,activity_type,body,created_by)
  VALUES(connection.organization_id,connection.id,activity,left(trim(COALESCE(p_note,'')),2000),auth.uid());
  RETURN public.get_circle_connection(connection.id);
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_circle_connection(
  p_connection_id UUID,p_person_id UUID DEFAULT NULL,p_first_name TEXT DEFAULT '',p_last_name TEXT DEFAULT '',p_email TEXT DEFAULT '',p_phone TEXT DEFAULT ''
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE connection public.circle_guest_connections%ROWTYPE; person_id UUID:=p_person_id; created_new BOOLEAN:=false;
BEGIN
  SELECT * INTO connection FROM public.circle_guest_connections WHERE id=p_connection_id FOR UPDATE;
  IF connection.id IS NULL OR connection.cell_group_id IS NULL THEN RAISE EXCEPTION 'Assign this guest to a Circle before connecting them to SheepCount'; END IF;
  IF NOT (public.circle_is_org_admin(connection.organization_id) OR public.circle_can_lead_group(connection.cell_group_id)) THEN RAISE EXCEPTION 'Leader access required'; END IF;
  IF connection.converted_person_id IS NOT NULL THEN RETURN jsonb_build_object('personId',connection.converted_person_id,'created',false,'alreadyConnected',true); END IF;
  IF person_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.people person WHERE person.id=person_id AND person.organization_id=connection.organization_id) THEN RAISE EXCEPTION 'Person is outside this organization'; END IF;
  IF person_id IS NULL THEN
    SELECT person.id INTO person_id FROM public.people person WHERE person.organization_id=connection.organization_id AND ((COALESCE(NULLIF(trim(p_email),''),connection.email)<>'' AND lower(person.email)=lower(COALESCE(NULLIF(trim(p_email),''),connection.email))) OR (COALESCE(NULLIF(trim(p_phone),''),connection.phone)<>'' AND person.phone=COALESCE(NULLIF(trim(p_phone),''),connection.phone))) ORDER BY person.created_at LIMIT 1;
    IF person_id IS NOT NULL THEN RAISE EXCEPTION 'A matching SheepCount person already exists. Select that person instead'; END IF;
    IF nullif(trim(p_first_name),'') IS NULL OR nullif(trim(p_last_name),'') IS NULL THEN RAISE EXCEPTION 'First and last name are required for a new visitor'; END IF;
    INSERT INTO public.people(organization_id,household_id,first_name,last_name,email,phone,birthdate,role,status,membership_type,evangelism_stage,is_prospect,join_date)
    VALUES(connection.organization_id,NULL,trim(p_first_name),trim(p_last_name),lower(COALESCE(NULLIF(trim(p_email),''),connection.email)),COALESCE(NULLIF(trim(p_phone),''),connection.phone),NULL,'Single','Active','Prospect','Small Group',true,current_date)
    RETURNING id INTO person_id; created_new:=true;
  END IF;
  INSERT INTO public.cell_group_members(cell_group_id,person_id,role) VALUES(connection.cell_group_id,person_id,'Member') ON CONFLICT(cell_group_id,person_id) DO NOTHING;
  UPDATE public.circle_guest_connections SET converted_person_id=person_id,status='connected',last_activity_at=now(),updated_at=now() WHERE id=connection.id;
  UPDATE public.circle_guest_rsvps SET converted_person_id=person_id,updated_at=now() WHERE connection_id=connection.id;
  UPDATE public.circle_join_interests SET status='closed',updated_at=now() WHERE connection_id=connection.id;
  INSERT INTO public.circle_guest_connection_activities(organization_id,connection_id,activity_type,body,created_by)
  VALUES(connection.organization_id,connection.id,'converted',CASE WHEN created_new THEN 'Registered as a SheepCount visitor.' ELSE 'Matched to an existing SheepCount person.' END,auth.uid());
  RETURN jsonb_build_object('personId',person_id,'created',created_new,'alreadyConnected',false);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_connection_attention_count()
RETURNS INT LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT count(*)::int FROM public.circle_guest_connections connection
  WHERE connection.follow_up_opt_in AND connection.status='new' AND (
    public.circle_is_org_admin(connection.organization_id) OR
    (connection.cell_group_id IS NULL AND public.circle_can_lead_organization(connection.organization_id)) OR
    (connection.cell_group_id IS NOT NULL AND public.circle_can_lead_group(connection.cell_group_id))
  );
$$;

CREATE OR REPLACE FUNCTION public.review_circle_content_assignment(
  p_content_type TEXT,p_content_id UUID,p_target_cell_group_id UUID DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_org UUID; v_old_group UUID; v_author UUID; v_has_participation BOOLEAN:=false;
BEGIN
  IF p_content_type NOT IN('gathering','gallery','testimony','announcement') THEN RAISE EXCEPTION 'Unsupported content type'; END IF;
  IF p_content_type NOT IN('announcement','gathering') AND p_target_cell_group_id IS NULL THEN RAISE EXCEPTION 'A Circle assignment is required'; END IF;
  IF p_content_type='gathering' THEN
    SELECT gathering.organization_id,gathering.cell_group_id,
      (gathering.attendance_session_id IS NOT NULL OR EXISTS(SELECT 1 FROM public.circle_gathering_attendance_records attendance WHERE attendance.gathering_id=gathering.id) OR EXISTS(SELECT 1 FROM public.circle_gathering_rsvps rsvp WHERE rsvp.gathering_id=gathering.id) OR EXISTS(SELECT 1 FROM public.circle_guest_rsvps rsvp WHERE rsvp.gathering_id=gathering.id))
    INTO v_org,v_old_group,v_has_participation FROM public.circle_gatherings gathering WHERE gathering.id=p_content_id;
  ELSIF p_content_type='gallery' THEN SELECT organization_id,cell_group_id INTO v_org,v_old_group FROM public.circle_galleries WHERE id=p_content_id;
  ELSIF p_content_type='testimony' THEN SELECT organization_id,cell_group_id,author_person_id INTO v_org,v_old_group,v_author FROM public.circle_testimonies WHERE id=p_content_id;
  ELSE SELECT organization_id,cell_group_id INTO v_org,v_old_group FROM public.circle_announcements WHERE id=p_content_id; END IF;
  IF v_org IS NULL OR NOT public.circle_is_org_admin(v_org) THEN RAISE EXCEPTION 'Organization admin access required'; END IF;
  IF p_target_cell_group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.cell_groups WHERE id=p_target_cell_group_id AND organization_id=v_org AND status='active') THEN RAISE EXCEPTION 'Choose an active Circle in this organization'; END IF;
  IF p_content_type='gathering' AND p_target_cell_group_id IS DISTINCT FROM v_old_group AND v_has_participation THEN RAISE EXCEPTION 'A gathering with RSVPs or attendance cannot be moved'; END IF;
  IF p_content_type='testimony' AND p_target_cell_group_id IS DISTINCT FROM v_old_group AND v_author IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.cell_group_members WHERE cell_group_id=p_target_cell_group_id AND person_id=v_author) THEN RAISE EXCEPTION 'The testimony author is not a member of the destination Circle'; END IF;
  IF p_content_type='gathering' THEN
    UPDATE public.circle_gatherings SET cell_group_id=p_target_cell_group_id,scope=CASE WHEN p_target_cell_group_id IS NULL THEN 'organization' ELSE 'circle' END,assignment_confirmed_at=now(),assignment_confirmed_by=auth.uid(),updated_at=now() WHERE id=p_content_id;
  ELSIF p_content_type='gallery' THEN UPDATE public.circle_galleries SET cell_group_id=p_target_cell_group_id,assignment_confirmed_at=now(),assignment_confirmed_by=auth.uid(),updated_at=now() WHERE id=p_content_id;
  ELSIF p_content_type='testimony' THEN UPDATE public.circle_testimonies SET cell_group_id=p_target_cell_group_id,assignment_confirmed_at=now(),assignment_confirmed_by=auth.uid(),updated_at=now() WHERE id=p_content_id;
  ELSE UPDATE public.circle_announcements SET cell_group_id=p_target_cell_group_id,assignment_confirmed_at=now(),assignment_confirmed_by=auth.uid(),updated_at=now() WHERE id=p_content_id; END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_circle_connection(UUID,TEXT,TEXT,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_circle_connection(UUID,TEXT,TEXT,UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.get_circle_dashboard() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_circle_dashboard() TO authenticated;
REVOKE ALL ON FUNCTION public.circle_can_lead_organization(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.circle_can_lead_organization(UUID) TO authenticated;

COMMIT;
