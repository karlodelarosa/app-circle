BEGIN;

ALTER TABLE public.circle_galleries
  ADD COLUMN IF NOT EXISTS is_organization_highlight BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS highlighted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS highlighted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS circle_galleries_organization_highlights_idx
  ON public.circle_galleries(organization_id, highlighted_at DESC)
  WHERE is_organization_highlight AND status = 'published';

CREATE OR REPLACE FUNCTION public.prepare_circle_gallery_highlight()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  gathering public.circle_gatherings%ROWTYPE;
  was_highlight BOOLEAN := false;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    was_highlight := OLD.is_organization_highlight;
  END IF;
  IF NEW.is_organization_highlight IS DISTINCT FROM was_highlight THEN
    IF NOT (
      public.circle_is_org_admin(NEW.organization_id)
      OR (NEW.cell_group_id IS NOT NULL AND public.circle_can_lead_group(NEW.cell_group_id))
    ) THEN
      RAISE EXCEPTION 'Circle leader or organization administrator access required';
    END IF;
  END IF;

  IF NEW.is_organization_highlight THEN
    IF NEW.status <> 'published' OR NEW.gathering_id IS NULL THEN
      RAISE EXCEPTION 'Organization highlights require a published gallery linked to a completed gathering';
    END IF;
    SELECT * INTO gathering
    FROM public.circle_gatherings
    WHERE id = NEW.gathering_id;
    IF gathering.id IS NULL
      OR gathering.organization_id <> NEW.organization_id
      OR gathering.cell_group_id IS DISTINCT FROM NEW.cell_group_id
      OR gathering.status <> 'completed' THEN
      RAISE EXCEPTION 'The highlight gathering must be completed and belong to the same Circle';
    END IF;
    IF NOT was_highlight THEN
      NEW.highlighted_at := now();
      NEW.highlighted_by := auth.uid();
    ELSE
      NEW.highlighted_at := COALESCE(OLD.highlighted_at, NEW.highlighted_at, now());
      NEW.highlighted_by := COALESCE(OLD.highlighted_by, NEW.highlighted_by, auth.uid());
    END IF;
  ELSE
    NEW.highlighted_at := NULL;
    NEW.highlighted_by := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS circle_gallery_highlight_guard ON public.circle_galleries;
CREATE TRIGGER circle_gallery_highlight_guard
BEFORE INSERT OR UPDATE ON public.circle_galleries
FOR EACH ROW EXECUTE FUNCTION public.prepare_circle_gallery_highlight();

REVOKE ALL ON FUNCTION public.prepare_circle_gallery_highlight() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_circle_dashboard()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_org UUID; v_person UUID; v_admin BOOLEAN; result JSONB;
BEGIN
  SELECT membership.organization_id,true INTO v_org,v_admin
  FROM public.organization_members membership
  WHERE membership.user_id=auth.uid() AND membership.status='active' AND membership.role='admin'
  ORDER BY membership.created_at LIMIT 1;
  IF v_org IS NULL THEN
    SELECT link.organization_id,false INTO v_org,v_admin
    FROM public.circle_user_links link
    WHERE link.user_id=auth.uid() AND link.status='active'
    ORDER BY link.created_at LIMIT 1;
  END IF;
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
      'id',gallery.id,'organizationId',gallery.organization_id,'gatheringId',gallery.gathering_id,'groupId',gallery.cell_group_id,'destinationName',group_row.name,
      'slug',gallery.public_slug,'title',gallery.title,'description',gallery.description,'coverUrl',gallery.cover_url,
      'publishedAt',gallery.published_at,'assignmentConfirmedAt',gallery.assignment_confirmed_at,
      'isOrganizationHighlight',gallery.is_organization_highlight,'highlightedAt',gallery.highlighted_at,
      'photos',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',photo.id,'imageUrl',photo.image_url,'caption',photo.caption,'altText',photo.alt_text) ORDER BY photo.display_order) FROM public.circle_gallery_photos photo WHERE photo.gallery_id=gallery.id),'[]'::jsonb)
    ) ORDER BY gallery.published_at DESC) FROM public.circle_galleries gallery JOIN accessible_groups group_row ON group_row.id=gallery.cell_group_id
      WHERE gallery.organization_id=v_org AND gallery.status='published' AND gallery.assignment_confirmed_at IS NOT NULL),'[]'::jsonb),
    'highlights',COALESCE((SELECT jsonb_agg(highlight.item ORDER BY highlight.highlighted_at DESC) FROM (
      SELECT gallery.highlighted_at,jsonb_build_object(
        'id',gallery.id,'organizationId',gallery.organization_id,'gatheringId',gallery.gathering_id,'groupId',gallery.cell_group_id,
        'destinationName',group_row.name,'slug',gallery.public_slug,'title',gallery.title,'description',gallery.description,
        'coverUrl',gallery.cover_url,'publishedAt',gallery.published_at,'assignmentConfirmedAt',gallery.assignment_confirmed_at,
        'isOrganizationHighlight',true,'highlightedAt',gallery.highlighted_at,
        'photos',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',photo.id,'imageUrl',photo.image_url,'caption',photo.caption,'altText',photo.alt_text) ORDER BY photo.display_order) FROM public.circle_gallery_photos photo WHERE photo.gallery_id=gallery.id AND photo.is_published),'[]'::jsonb)
      ) AS item
      FROM public.circle_galleries gallery
      JOIN public.cell_groups group_row ON group_row.id=gallery.cell_group_id
      WHERE gallery.organization_id=v_org AND gallery.status='published' AND gallery.assignment_confirmed_at IS NOT NULL
        AND gallery.is_organization_highlight
      ORDER BY gallery.highlighted_at DESC
      LIMIT 3
    ) highlight),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;

COMMIT;
