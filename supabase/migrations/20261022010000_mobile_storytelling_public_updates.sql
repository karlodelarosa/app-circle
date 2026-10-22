BEGIN;

ALTER TABLE public.circle_announcements
  ADD COLUMN IF NOT EXISTS is_public BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS circle_announcements_public_idx
  ON public.circle_announcements(organization_id, published_at DESC)
  WHERE is_public;

CREATE OR REPLACE FUNCTION public.get_circle_public_space(p_org_slug TEXT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
 SELECT jsonb_build_object(
   'organization',jsonb_build_object('id',o.id,'slug',o.slug,'name',o.name,'imageUrl',o.image,'subscriptionStatus',o.status,'circlesEnabled',true),
   'introduction',s.introduction,
   'heroTitle',s.hero_title,
   'heroImageUrl',s.hero_image_url,
   'announcements',COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
       'id',a.id,'organizationId',a.organization_id,'groupId',a.cell_group_id,
       'title',a.title,'body',a.body,'publishedAt',a.published_at,
       'expiresAt',a.expires_at,'isPublic',true
     ) ORDER BY a.published_at DESC)
     FROM public.circle_announcements a
     WHERE a.organization_id=o.id AND a.is_public
       AND (a.expires_at IS NULL OR a.expires_at>now())
   ),'[]'::jsonb),
   'gatherings',COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
       'id',g.id,'organizationId',g.organization_id,'groupId',g.cell_group_id,
       'slug',g.public_slug,'title',g.title,'meetingDate',g.starts_at,
       'location',g.location,'studyTopic',g.study_topic,'notes',g.notes,
       'summary',g.summary,'coverUrl',g.cover_url,'status',g.status,
       'createdBy',g.created_by,'visibility',g.visibility,
       'publishedAt',g.published_at,'guestRsvpEnabled',g.guest_rsvp_enabled,
       'rsvps','{}'::jsonb
     ) ORDER BY g.starts_at)
     FROM public.circle_gatherings g
     WHERE g.organization_id=o.id AND g.visibility='public'
       AND g.published_at IS NOT NULL AND g.status='scheduled'
       AND g.starts_at>=now()
   ),'[]'::jsonb),
   'testimonies',COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
       'id',t.id,'organizationId',t.organization_id,'groupId',t.cell_group_id,
       'slug',t.public_slug,'title',t.title,'body',t.body,
       'authorName',t.author_display_name,'imageUrl',t.image_url,
       'publishedAt',t.published_at
     ) ORDER BY t.published_at DESC)
     FROM public.circle_testimonies t
     WHERE t.organization_id=o.id AND t.status='published'
   ),'[]'::jsonb),
   'galleries',COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
       'id',ga.id,'organizationId',ga.organization_id,
       'gatheringId',ga.gathering_id,'groupId',ga.cell_group_id,
       'slug',ga.public_slug,'title',ga.title,'description',ga.description,
       'coverUrl',ga.cover_url,'publishedAt',ga.published_at,
       'photos',COALESCE((
         SELECT jsonb_agg(jsonb_build_object(
           'id',ph.id,'imageUrl',ph.image_url,'caption',ph.caption,
           'altText',ph.alt_text
         ) ORDER BY ph.display_order)
         FROM public.circle_gallery_photos ph
         WHERE ph.gallery_id=ga.id AND ph.is_published
       ),'[]'::jsonb)
     ) ORDER BY ga.published_at DESC)
     FROM public.circle_galleries ga
     WHERE ga.organization_id=o.id AND ga.status='published'
   ),'[]'::jsonb),
   'circles',COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
       'id',cg.id,'organizationId',cg.organization_id,'slug',l.public_slug,
       'name',cg.name,'description',COALESCE(NULLIF(l.description,''),cg.description),
       'regularSchedule','','location',cg.location,'leaderId',cg.leader_person_id,
       'role','member','coverUrl',l.cover_url,'isPublic',true
     ) ORDER BY cg.name)
     FROM public.circle_public_listings l
     JOIN public.cell_groups cg ON cg.id=l.cell_group_id
     WHERE l.organization_id=o.id AND l.is_published
   ),'[]'::jsonb)
 )
 FROM public.organizations o
 JOIN public.circle_public_spaces s
   ON s.organization_id=o.id AND s.is_published
 WHERE o.slug=p_org_slug AND o.status='active'
 LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_public_gathering(
  p_org_slug TEXT,
  p_gathering_slug TEXT
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
 SELECT jsonb_build_object(
   'organization',jsonb_build_object('id',o.id,'slug',o.slug,'name',o.name),
   'gathering',jsonb_build_object(
     'id',g.id,'organizationId',g.organization_id,'groupId',g.cell_group_id,
     'slug',g.public_slug,'title',g.title,'meetingDate',g.starts_at,
     'location',g.location,'studyTopic',g.study_topic,'notes',g.notes,
     'summary',g.summary,'coverUrl',g.cover_url,'status',g.status,
     'createdBy',g.created_by,'visibility',g.visibility,
     'publishedAt',g.published_at,'guestRsvpEnabled',g.guest_rsvp_enabled,
     'rsvps','{}'::jsonb
   )
 )
 FROM public.organizations o
 JOIN public.circle_public_spaces s ON s.organization_id=o.id AND s.is_published
 JOIN public.circle_gatherings g ON g.organization_id=o.id
 WHERE o.slug=p_org_slug AND o.status='active'
   AND g.public_slug=p_gathering_slug AND g.visibility='public'
   AND g.published_at IS NOT NULL AND g.status='scheduled'
 LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.submit_circle_guest_rsvp(p_gathering_id UUID,p_name TEXT,p_email TEXT,p_phone TEXT,p_status TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE g public.circle_gatherings%ROWTYPE; contact TEXT; rid UUID; cid UUID;
BEGIN
  SELECT * INTO g FROM public.circle_gatherings WHERE id=p_gathering_id AND visibility='public' AND published_at IS NOT NULL AND guest_rsvp_enabled AND status='scheduled' AND starts_at>=now()
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

GRANT EXECUTE ON FUNCTION public.get_circle_public_space(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_circle_public_gathering(TEXT,TEXT) TO anon, authenticated;

COMMIT;
