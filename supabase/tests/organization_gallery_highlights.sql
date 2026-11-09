-- Run against a linked, non-production SheepCount staging database.
-- All fixtures and writes are rolled back.
BEGIN;

DO $$
DECLARE
  organization_id UUID;
  group_id UUID;
  admin_id UUID;
  member_id UUID;
  other_organization_id UUID := gen_random_uuid();
  other_group_id UUID := gen_random_uuid();
  sibling_group_id UUID := gen_random_uuid();
  completed_gathering_id UUID := gen_random_uuid();
  scheduled_gathering_id UUID := gen_random_uuid();
  cross_circle_gathering_id UUID := gen_random_uuid();
  cross_organization_gathering_id UUID := gen_random_uuid();
  gallery_id UUID := gen_random_uuid();
  rejected BOOLEAN := false;
  highlighted TIMESTAMPTZ;
BEGIN
  SELECT membership.organization_id,membership.user_id,group_row.id
  INTO organization_id,admin_id,group_id
  FROM public.organization_members membership
  JOIN public.cell_groups group_row ON group_row.organization_id=membership.organization_id AND group_row.status='active'
  WHERE membership.role='admin' AND membership.status='active'
  ORDER BY membership.created_at,group_row.created_at
  LIMIT 1;

  SELECT link.user_id INTO member_id
  FROM public.circle_user_links link
  JOIN public.cell_group_members membership ON membership.person_id=link.person_id AND membership.cell_group_id=group_id
  JOIN public.cell_groups group_row ON group_row.id=membership.cell_group_id
  WHERE link.organization_id=organization_id AND link.status='active'
    AND membership.role<>'Leader' AND group_row.leader_person_id IS DISTINCT FROM link.person_id
  ORDER BY link.created_at
  LIMIT 1;

  IF organization_id IS NULL OR group_id IS NULL OR admin_id IS NULL OR member_id IS NULL THEN
    RAISE EXCEPTION 'Highlight test requires an organization admin, active Circle, and linked ordinary member';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',admin_id::text,true);
  INSERT INTO public.organizations(id,name,slug)
  VALUES (other_organization_id,'Highlight test organization','highlight-test-'||left(other_organization_id::text,8));
  INSERT INTO public.cell_groups(id,organization_id,name)
  VALUES
    (sibling_group_id,organization_id,'Highlight sibling Circle'),
    (other_group_id,other_organization_id,'Highlight external Circle');
  INSERT INTO public.circle_gatherings(
    id,organization_id,cell_group_id,scope,title,starts_at,ends_at,location,status,created_by,public_slug
  ) VALUES
    (completed_gathering_id,organization_id,group_id,'circle','Highlight completed fixture',now()-interval '2 days',now()-interval '2 days'+interval '2 hours','Test location','completed',admin_id,'highlight-completed-'||left(completed_gathering_id::text,8)),
    (scheduled_gathering_id,organization_id,group_id,'circle','Highlight scheduled fixture',now()+interval '2 days',now()+interval '2 days'+interval '2 hours','Test location','scheduled',admin_id,'highlight-scheduled-'||left(scheduled_gathering_id::text,8)),
    (cross_circle_gathering_id,organization_id,sibling_group_id,'circle','Highlight sibling Circle fixture',now()-interval '3 days',now()-interval '3 days'+interval '2 hours','Test location','completed',admin_id,'highlight-sibling-'||left(cross_circle_gathering_id::text,8)),
    (cross_organization_gathering_id,other_organization_id,other_group_id,'circle','Highlight external organization fixture',now()-interval '4 days',now()-interval '4 days'+interval '2 hours','Test location','completed',admin_id,'highlight-external-'||left(cross_organization_gathering_id::text,8));

  INSERT INTO public.circle_galleries(
    id,organization_id,gathering_id,cell_group_id,public_slug,title,description,status,published_at,created_by
  ) VALUES (
    gallery_id,organization_id,scheduled_gathering_id,group_id,'highlight-test-'||left(gallery_id::text,8),
    'Organization highlight fixture','Rolled back after verification.','published',now(),admin_id
  );

  BEGIN
    UPDATE public.circle_galleries SET is_organization_highlight=true WHERE id=gallery_id;
  EXCEPTION WHEN OTHERS THEN
    rejected:=true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'A non-completed gathering was accepted as an organization highlight';
  END IF;

  rejected:=false;
  BEGIN
    UPDATE public.circle_galleries
    SET gathering_id=cross_circle_gathering_id,is_organization_highlight=true
    WHERE id=gallery_id;
  EXCEPTION WHEN OTHERS THEN
    rejected:=true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'A gathering from another Circle was accepted as an organization highlight';
  END IF;

  rejected:=false;
  BEGIN
    UPDATE public.circle_galleries
    SET gathering_id=cross_organization_gathering_id,is_organization_highlight=true
    WHERE id=gallery_id;
  EXCEPTION WHEN OTHERS THEN
    rejected:=true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'A gathering from another organization was accepted as an organization highlight';
  END IF;

  UPDATE public.circle_galleries
  SET gathering_id=completed_gathering_id,is_organization_highlight=true
  WHERE id=gallery_id;
  SELECT highlighted_at INTO highlighted FROM public.circle_galleries WHERE id=gallery_id;
  IF highlighted IS NULL THEN
    RAISE EXCEPTION 'A valid organization highlight did not receive a publication timestamp';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',member_id::text,true);
  rejected:=false;
  BEGIN
    UPDATE public.circle_galleries SET is_organization_highlight=false WHERE id=gallery_id;
  EXCEPTION WHEN OTHERS THEN
    rejected:=true;
  END;
  IF NOT rejected OR NOT EXISTS (
    SELECT 1 FROM public.circle_galleries WHERE id=gallery_id AND is_organization_highlight
  ) THEN
    RAISE EXCEPTION 'An ordinary Circle member changed organization highlight visibility';
  END IF;
END;
$$;

ROLLBACK;
