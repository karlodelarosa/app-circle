BEGIN;

ALTER TABLE public.circle_gatherings
  ADD COLUMN IF NOT EXISTS assignment_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS assignment_confirmed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.circle_galleries
  ADD COLUMN IF NOT EXISTS assignment_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS assignment_confirmed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.circle_testimonies
  ADD COLUMN IF NOT EXISTS assignment_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS assignment_confirmed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.circle_announcements
  ADD COLUMN IF NOT EXISTS assignment_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS assignment_confirmed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.circle_galleries ALTER COLUMN cell_group_id SET NOT NULL;
ALTER TABLE public.circle_testimonies ALTER COLUMN cell_group_id SET NOT NULL;

CREATE TABLE IF NOT EXISTS public.circle_content_assignment_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  content_type TEXT NOT NULL CHECK (content_type IN ('gathering','gallery','testimony','announcement')),
  content_id UUID NOT NULL,
  previous_cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE SET NULL,
  next_cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE SET NULL,
  action TEXT NOT NULL CHECK (action IN ('confirmed','reassigned')),
  performed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS circle_content_assignment_audit_item_idx
  ON public.circle_content_assignment_audit(organization_id, content_type, content_id, created_at DESC);

ALTER TABLE public.circle_content_assignment_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins read content assignment audit" ON public.circle_content_assignment_audit;
CREATE POLICY "Admins read content assignment audit"
ON public.circle_content_assignment_audit FOR SELECT TO authenticated
USING (public.circle_is_org_admin(organization_id));

CREATE OR REPLACE FUNCTION public.circle_content_assignment_guard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_type TEXT := CASE TG_TABLE_NAME
    WHEN 'circle_gatherings' THEN 'gathering'
    WHEN 'circle_galleries' THEN 'gallery'
    WHEN 'circle_testimonies' THEN 'testimony'
    WHEN 'circle_announcements' THEN 'announcement'
  END;
  v_group_org UUID;
BEGIN
  IF NEW.cell_group_id IS NULL AND v_type <> 'announcement' THEN
    RAISE EXCEPTION 'A Circle assignment is required';
  END IF;
  IF NEW.cell_group_id IS NULL AND v_type = 'announcement'
    AND NOT public.circle_is_org_admin(NEW.organization_id) THEN
    RAISE EXCEPTION 'Only organization administrators can publish organization-wide announcements';
  END IF;
  IF NEW.cell_group_id IS NOT NULL THEN
    SELECT organization_id INTO v_group_org
    FROM public.cell_groups
    WHERE id = NEW.cell_group_id AND status = 'active';
    IF v_group_org IS NULL OR v_group_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'The content destination must be an active Circle in the same organization';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.assignment_confirmed_at := COALESCE(NEW.assignment_confirmed_at, now());
    NEW.assignment_confirmed_by := COALESCE(NEW.assignment_confirmed_by, auth.uid());
    RETURN NEW;
  END IF;

  IF NEW.cell_group_id IS DISTINCT FROM OLD.cell_group_id THEN
    IF NOT public.circle_is_org_admin(NEW.organization_id) THEN
      RAISE EXCEPTION 'Only organization administrators can reassign existing content';
    END IF;
    NEW.assignment_confirmed_at := now();
    NEW.assignment_confirmed_by := auth.uid();
    INSERT INTO public.circle_content_assignment_audit(
      organization_id, content_type, content_id, previous_cell_group_id,
      next_cell_group_id, action, performed_by
    ) VALUES (
      NEW.organization_id, v_type, NEW.id, OLD.cell_group_id,
      NEW.cell_group_id, 'reassigned', auth.uid()
    );
  ELSIF OLD.assignment_confirmed_at IS NULL AND NEW.assignment_confirmed_at IS NOT NULL THEN
    IF NOT public.circle_is_org_admin(NEW.organization_id) THEN
      RAISE EXCEPTION 'Only organization administrators can confirm legacy content assignments';
    END IF;
    NEW.assignment_confirmed_at := now();
    NEW.assignment_confirmed_by := auth.uid();
    INSERT INTO public.circle_content_assignment_audit(
      organization_id, content_type, content_id, previous_cell_group_id,
      next_cell_group_id, action, performed_by
    ) VALUES (
      NEW.organization_id, v_type, NEW.id, OLD.cell_group_id,
      NEW.cell_group_id, 'confirmed', auth.uid()
    );
  ELSIF OLD.assignment_confirmed_at IS NOT NULL AND NEW.assignment_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'A confirmed content assignment cannot be returned to review';
  ELSE
    NEW.assignment_confirmed_at := OLD.assignment_confirmed_at;
    NEW.assignment_confirmed_by := OLD.assignment_confirmed_by;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS circle_gathering_assignment_guard ON public.circle_gatherings;
CREATE TRIGGER circle_gathering_assignment_guard
BEFORE INSERT OR UPDATE ON public.circle_gatherings
FOR EACH ROW EXECUTE FUNCTION public.circle_content_assignment_guard();
DROP TRIGGER IF EXISTS circle_gallery_assignment_guard ON public.circle_galleries;
CREATE TRIGGER circle_gallery_assignment_guard
BEFORE INSERT OR UPDATE ON public.circle_galleries
FOR EACH ROW EXECUTE FUNCTION public.circle_content_assignment_guard();
DROP TRIGGER IF EXISTS circle_testimony_assignment_guard ON public.circle_testimonies;
CREATE TRIGGER circle_testimony_assignment_guard
BEFORE INSERT OR UPDATE ON public.circle_testimonies
FOR EACH ROW EXECUTE FUNCTION public.circle_content_assignment_guard();
DROP TRIGGER IF EXISTS circle_announcement_assignment_guard ON public.circle_announcements;
CREATE TRIGGER circle_announcement_assignment_guard
BEFORE INSERT OR UPDATE ON public.circle_announcements
FOR EACH ROW EXECUTE FUNCTION public.circle_content_assignment_guard();

CREATE OR REPLACE FUNCTION public.get_circle_content_assignments()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_org UUID;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.organization_members
  WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
  ORDER BY created_at LIMIT 1;
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organization admin access required'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', item.id,
      'type', item.content_type,
      'title', item.title,
      'groupId', item.cell_group_id,
      'groupName', group_row.name,
      'confirmedAt', item.assignment_confirmed_at,
      'publishedAt', item.published_at,
      'hasParticipation', item.has_participation
    ) ORDER BY item.assignment_confirmed_at NULLS FIRST, item.published_at DESC NULLS LAST, item.title)
    FROM (
      SELECT id, 'gathering'::TEXT AS content_type, title, cell_group_id,
        assignment_confirmed_at, published_at,
        (attendance_session_id IS NOT NULL OR EXISTS (
          SELECT 1 FROM public.circle_gathering_rsvps r WHERE r.gathering_id = circle_gatherings.id
        ) OR EXISTS (
          SELECT 1 FROM public.circle_guest_rsvps r WHERE r.gathering_id = circle_gatherings.id
        )) AS has_participation
      FROM public.circle_gatherings WHERE organization_id = v_org
      UNION ALL
      SELECT id, 'gallery', title, cell_group_id, assignment_confirmed_at, published_at, false
      FROM public.circle_galleries WHERE organization_id = v_org
      UNION ALL
      SELECT id, 'testimony', title, cell_group_id, assignment_confirmed_at, published_at, false
      FROM public.circle_testimonies WHERE organization_id = v_org
      UNION ALL
      SELECT id, 'announcement', title, cell_group_id, assignment_confirmed_at, published_at, false
      FROM public.circle_announcements WHERE organization_id = v_org
    ) item
    LEFT JOIN public.cell_groups group_row ON group_row.id = item.cell_group_id
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.review_circle_content_assignment(
  p_content_type TEXT,
  p_content_id UUID,
  p_target_cell_group_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org UUID;
  v_old_group UUID;
  v_author UUID;
  v_has_participation BOOLEAN := false;
BEGIN
  IF p_content_type NOT IN ('gathering','gallery','testimony','announcement') THEN
    RAISE EXCEPTION 'Unsupported content type';
  END IF;
  IF p_content_type <> 'announcement' AND p_target_cell_group_id IS NULL THEN
    RAISE EXCEPTION 'A Circle assignment is required';
  END IF;

  IF p_content_type = 'gathering' THEN
    SELECT organization_id, cell_group_id,
      (attendance_session_id IS NOT NULL OR EXISTS (
        SELECT 1 FROM public.circle_gathering_rsvps r WHERE r.gathering_id = circle_gatherings.id
      ) OR EXISTS (
        SELECT 1 FROM public.circle_guest_rsvps r WHERE r.gathering_id = circle_gatherings.id
      ))
    INTO v_org, v_old_group, v_has_participation
    FROM public.circle_gatherings WHERE id = p_content_id;
  ELSIF p_content_type = 'gallery' THEN
    SELECT organization_id, cell_group_id INTO v_org, v_old_group
    FROM public.circle_galleries WHERE id = p_content_id;
  ELSIF p_content_type = 'testimony' THEN
    SELECT organization_id, cell_group_id, author_person_id INTO v_org, v_old_group, v_author
    FROM public.circle_testimonies WHERE id = p_content_id;
  ELSE
    SELECT organization_id, cell_group_id INTO v_org, v_old_group
    FROM public.circle_announcements WHERE id = p_content_id;
  END IF;

  IF v_org IS NULL OR NOT public.circle_is_org_admin(v_org) THEN
    RAISE EXCEPTION 'Organization admin access required';
  END IF;
  IF p_target_cell_group_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.cell_groups
    WHERE id = p_target_cell_group_id AND organization_id = v_org AND status = 'active'
  ) THEN RAISE EXCEPTION 'Choose an active Circle in this organization'; END IF;
  IF p_content_type = 'gathering'
    AND p_target_cell_group_id IS DISTINCT FROM v_old_group
    AND v_has_participation THEN
    RAISE EXCEPTION 'A gathering with RSVPs or attendance cannot be moved';
  END IF;
  IF p_content_type = 'testimony'
    AND p_target_cell_group_id IS DISTINCT FROM v_old_group
    AND v_author IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.cell_group_members
      WHERE cell_group_id = p_target_cell_group_id AND person_id = v_author
    ) THEN RAISE EXCEPTION 'The testimony author is not a member of the destination Circle'; END IF;

  IF p_content_type = 'gathering' THEN
    UPDATE public.circle_gatherings SET cell_group_id = p_target_cell_group_id,
      assignment_confirmed_at = now(), assignment_confirmed_by = auth.uid(), updated_at = now()
    WHERE id = p_content_id;
  ELSIF p_content_type = 'gallery' THEN
    UPDATE public.circle_galleries SET cell_group_id = p_target_cell_group_id,
      assignment_confirmed_at = now(), assignment_confirmed_by = auth.uid(), updated_at = now()
    WHERE id = p_content_id;
  ELSIF p_content_type = 'testimony' THEN
    UPDATE public.circle_testimonies SET cell_group_id = p_target_cell_group_id,
      assignment_confirmed_at = now(), assignment_confirmed_by = auth.uid(), updated_at = now()
    WHERE id = p_content_id;
  ELSE
    UPDATE public.circle_announcements SET cell_group_id = p_target_cell_group_id,
      assignment_confirmed_at = now(), assignment_confirmed_by = auth.uid(), updated_at = now()
    WHERE id = p_content_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.get_circle_content_assignments() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_circle_content_assignment(TEXT, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_circle_content_assignments() TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_circle_content_assignment(TEXT, UUID, UUID) TO authenticated;

COMMIT;
