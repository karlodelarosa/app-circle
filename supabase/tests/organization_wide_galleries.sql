-- Run against linked, non-production staging. All fixtures are rolled back.
BEGIN;

DO $$
DECLARE
  organization_id UUID;
  admin_id UUID;
  member_id UUID;
  organization_gathering_id UUID:=gen_random_uuid();
  circle_gathering_id UUID;
  gallery_id UUID:=gen_random_uuid();
  rejected BOOLEAN:=false;
BEGIN
  SELECT membership.organization_id,membership.user_id
  INTO organization_id,admin_id
  FROM public.organization_members membership
  WHERE membership.role='admin' AND membership.status='active'
  ORDER BY membership.created_at LIMIT 1;

  SELECT link.user_id INTO member_id
  FROM public.circle_user_links link
  WHERE link.organization_id=organization_id AND link.status='active'
    AND link.user_id<>admin_id
  ORDER BY link.created_at LIMIT 1;

  SELECT gathering.id INTO circle_gathering_id
  FROM public.circle_gatherings gathering
  WHERE gathering.organization_id=organization_id AND gathering.scope='circle'
    AND gathering.status='completed'
  ORDER BY gathering.starts_at DESC LIMIT 1;

  IF organization_id IS NULL OR admin_id IS NULL OR member_id IS NULL OR circle_gathering_id IS NULL THEN
    RAISE EXCEPTION 'Organization gallery test requires an admin, linked user, and completed Circle gathering';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',admin_id::text,true);
  INSERT INTO public.circle_gatherings(
    id,organization_id,cell_group_id,scope,title,starts_at,ends_at,status,created_by,assignment_confirmed_at
  ) VALUES(
    organization_gathering_id,organization_id,NULL,'organization','Organization gallery fixture',
    now()-interval '2 days',now()-interval '2 days'+interval '2 hours','completed',admin_id,now()
  );

  INSERT INTO public.circle_galleries(
    id,organization_id,gathering_id,cell_group_id,public_slug,title,status,published_at,created_by
  ) VALUES(
    gallery_id,organization_id,organization_gathering_id,NULL,
    'organization-gallery-'||left(gallery_id::text,8),'Organization gallery fixture','published',now(),admin_id
  );

  IF NOT EXISTS(
    SELECT 1 FROM public.circle_galleries gallery
    WHERE gallery.id=gallery_id AND gallery.cell_group_id IS NULL
      AND gallery.is_organization_highlight AND gallery.highlighted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Organization gallery was not automatically highlighted';
  END IF;

  rejected:=false;
  BEGIN
    UPDATE public.circle_galleries SET gathering_id=circle_gathering_id WHERE id=gallery_id;
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Organization gallery accepted a Circle gathering'; END IF;

  PERFORM set_config('request.jwt.claim.sub',member_id::text,true);
  rejected:=false;
  BEGIN
    INSERT INTO public.circle_galleries(
      organization_id,gathering_id,cell_group_id,public_slug,title,status,published_at,created_by
    ) VALUES(
      organization_id,organization_gathering_id,NULL,
      'forged-organization-gallery-'||left(gen_random_uuid()::text,8),'Forged organization gallery','published',now(),member_id
    );
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Non-admin created an organization gallery'; END IF;
END;
$$;

ROLLBACK;
