BEGIN;

ALTER TABLE public.circle_galleries ALTER COLUMN cell_group_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.circle_content_assignment_guard()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_type TEXT := CASE TG_TABLE_NAME WHEN 'circle_gatherings' THEN 'gathering' WHEN 'circle_galleries' THEN 'gallery' WHEN 'circle_testimonies' THEN 'testimony' WHEN 'circle_announcements' THEN 'announcement' END;
  v_group_org UUID;
  v_scope TEXT := COALESCE(to_jsonb(NEW)->>'scope', CASE WHEN NEW.cell_group_id IS NULL THEN 'organization' ELSE 'circle' END);
BEGIN
  IF NEW.cell_group_id IS NULL AND v_type NOT IN ('announcement','gathering','gallery') THEN
    RAISE EXCEPTION 'A Circle assignment is required';
  END IF;
  IF v_type = 'gathering' AND ((v_scope = 'circle' AND NEW.cell_group_id IS NULL) OR (v_scope = 'organization' AND NEW.cell_group_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'The gathering destination does not match its scope';
  END IF;
  IF NEW.cell_group_id IS NULL AND v_type IN ('announcement','gallery') AND NOT public.circle_is_org_admin(NEW.organization_id) THEN
    RAISE EXCEPTION 'Only organization administrators can publish organization-wide content';
  END IF;
  IF NEW.cell_group_id IS NOT NULL THEN
    SELECT organization_id INTO v_group_org FROM public.cell_groups WHERE id=NEW.cell_group_id AND status='active';
    IF v_group_org IS NULL OR v_group_org<>NEW.organization_id THEN
      RAISE EXCEPTION 'The content destination must be an active Circle in the same organization';
    END IF;
  END IF;
  IF TG_OP='INSERT' THEN
    NEW.assignment_confirmed_at:=COALESCE(NEW.assignment_confirmed_at,now());
    NEW.assignment_confirmed_by:=COALESCE(NEW.assignment_confirmed_by,auth.uid());
    RETURN NEW;
  END IF;
  IF NEW.cell_group_id IS DISTINCT FROM OLD.cell_group_id THEN
    IF NOT public.circle_is_org_admin(NEW.organization_id) THEN
      RAISE EXCEPTION 'Only organization administrators can reassign existing content';
    END IF;
    NEW.assignment_confirmed_at:=now();
    NEW.assignment_confirmed_by:=auth.uid();
    INSERT INTO public.circle_content_assignment_audit(organization_id,content_type,content_id,previous_cell_group_id,next_cell_group_id,action,performed_by)
    VALUES(NEW.organization_id,v_type,NEW.id,OLD.cell_group_id,NEW.cell_group_id,'reassigned',auth.uid());
  ELSIF OLD.assignment_confirmed_at IS NULL AND NEW.assignment_confirmed_at IS NOT NULL THEN
    IF NOT public.circle_is_org_admin(NEW.organization_id) THEN
      RAISE EXCEPTION 'Only organization administrators can confirm legacy content assignments';
    END IF;
    NEW.assignment_confirmed_at:=now();
    NEW.assignment_confirmed_by:=auth.uid();
    INSERT INTO public.circle_content_assignment_audit(organization_id,content_type,content_id,previous_cell_group_id,next_cell_group_id,action,performed_by)
    VALUES(NEW.organization_id,v_type,NEW.id,OLD.cell_group_id,NEW.cell_group_id,'confirmed',auth.uid());
  ELSIF OLD.assignment_confirmed_at IS NOT NULL AND NEW.assignment_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'A confirmed content assignment cannot be returned to review';
  ELSE
    NEW.assignment_confirmed_at:=OLD.assignment_confirmed_at;
    NEW.assignment_confirmed_by:=OLD.assignment_confirmed_by;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.prepare_circle_gallery_highlight()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  gathering public.circle_gatherings%ROWTYPE;
  was_highlight BOOLEAN := false;
BEGIN
  IF TG_OP='UPDATE' THEN was_highlight:=OLD.is_organization_highlight; END IF;

  IF NEW.cell_group_id IS NULL THEN
    IF NOT public.circle_is_org_admin(NEW.organization_id) THEN
      RAISE EXCEPTION 'Organization administrator access required';
    END IF;
    NEW.is_organization_highlight:=true;
  ELSIF NEW.is_organization_highlight IS DISTINCT FROM was_highlight AND NOT (
    public.circle_is_org_admin(NEW.organization_id) OR public.circle_can_lead_group(NEW.cell_group_id)
  ) THEN
    RAISE EXCEPTION 'Circle leader or organization administrator access required';
  END IF;

  IF NEW.cell_group_id IS NULL OR NEW.is_organization_highlight THEN
    IF NEW.status<>'published' OR NEW.gathering_id IS NULL THEN
      RAISE EXCEPTION 'Organization highlights require a published gallery linked to a completed gathering';
    END IF;
    SELECT * INTO gathering FROM public.circle_gatherings WHERE id=NEW.gathering_id;
    IF gathering.id IS NULL OR gathering.organization_id<>NEW.organization_id OR gathering.status<>'completed' THEN
      RAISE EXCEPTION 'The gallery gathering must be completed and belong to the same organization';
    END IF;
    IF NEW.cell_group_id IS NULL THEN
      IF gathering.scope<>'organization' OR gathering.cell_group_id IS NOT NULL THEN
        RAISE EXCEPTION 'Organization galleries require a completed organization gathering';
      END IF;
    ELSIF gathering.scope<>'circle' OR gathering.cell_group_id IS DISTINCT FROM NEW.cell_group_id THEN
      RAISE EXCEPTION 'Circle highlights require a completed gathering from the same Circle';
    END IF;
    NEW.highlighted_at:=CASE WHEN NOT was_highlight THEN now() ELSE COALESCE(OLD.highlighted_at,NEW.highlighted_at,now()) END;
    NEW.highlighted_by:=CASE WHEN NOT was_highlight THEN auth.uid() ELSE COALESCE(OLD.highlighted_by,NEW.highlighted_by,auth.uid()) END;
  ELSE
    NEW.highlighted_at:=NULL;
    NEW.highlighted_by:=NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_circle_content_assignment(
  p_content_type TEXT,p_content_id UUID,p_target_cell_group_id UUID DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_org UUID; v_old_group UUID; v_author UUID; v_has_participation BOOLEAN:=false;
  v_gallery_gathering UUID;
BEGIN
  IF p_content_type NOT IN('gathering','gallery','testimony','announcement') THEN RAISE EXCEPTION 'Unsupported content type'; END IF;
  IF p_content_type='testimony' AND p_target_cell_group_id IS NULL THEN RAISE EXCEPTION 'A Circle assignment is required'; END IF;
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
  ELSIF p_content_type='gallery' THEN
    IF p_target_cell_group_id IS NULL THEN
      SELECT id INTO v_gallery_gathering FROM public.circle_gatherings
      WHERE organization_id=v_org AND scope='organization' AND cell_group_id IS NULL AND status='completed' AND assignment_confirmed_at IS NOT NULL
      ORDER BY starts_at DESC LIMIT 1;
      IF v_gallery_gathering IS NULL THEN RAISE EXCEPTION 'A completed organization gathering is required'; END IF;
      UPDATE public.circle_galleries SET cell_group_id=NULL,gathering_id=v_gallery_gathering,is_organization_highlight=true,assignment_confirmed_at=now(),assignment_confirmed_by=auth.uid(),updated_at=now() WHERE id=p_content_id;
    ELSE
      SELECT gathering.id INTO v_gallery_gathering FROM public.circle_galleries gallery
      JOIN public.circle_gatherings gathering ON gathering.id=gallery.gathering_id
      WHERE gallery.id=p_content_id AND gathering.organization_id=v_org AND gathering.cell_group_id=p_target_cell_group_id AND gathering.scope='circle' AND gathering.status='completed';
      UPDATE public.circle_galleries SET cell_group_id=p_target_cell_group_id,gathering_id=v_gallery_gathering,is_organization_highlight=false,assignment_confirmed_at=now(),assignment_confirmed_by=auth.uid(),updated_at=now() WHERE id=p_content_id;
    END IF;
  ELSIF p_content_type='testimony' THEN
    UPDATE public.circle_testimonies SET cell_group_id=p_target_cell_group_id,assignment_confirmed_at=now(),assignment_confirmed_by=auth.uid(),updated_at=now() WHERE id=p_content_id;
  ELSE
    UPDATE public.circle_announcements SET cell_group_id=p_target_cell_group_id,assignment_confirmed_at=now(),assignment_confirmed_by=auth.uid(),updated_at=now() WHERE id=p_content_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.circle_content_assignment_guard() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.prepare_circle_gallery_highlight() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.review_circle_content_assignment(TEXT,UUID,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.review_circle_content_assignment(TEXT,UUID,UUID) TO authenticated;

COMMIT;
