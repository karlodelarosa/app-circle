BEGIN;

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

COMMIT;
