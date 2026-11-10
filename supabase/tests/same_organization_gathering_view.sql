-- Run against linked, non-production staging. All fixtures are rolled back.
BEGIN;

CREATE TEMP TABLE gathering_view_fixture AS
SELECT
  membership.organization_id,
  membership.user_id AS admin_id,
  link.user_id AS viewer_id,
  link.person_id AS viewer_person_id,
  member.cell_group_id AS viewer_group_id,
  gen_random_uuid() AS sibling_group_id,
  gen_random_uuid() AS gathering_id,
  gen_random_uuid() AS viewer_reflection_id,
  gen_random_uuid() AS guest_id
FROM public.organization_members membership
JOIN public.circle_user_links link ON link.organization_id=membership.organization_id AND link.status='active'
JOIN public.cell_group_members member ON member.person_id=link.person_id
WHERE membership.role='admin' AND membership.status='active'
  AND link.user_id<>membership.user_id
ORDER BY membership.created_at,link.created_at
LIMIT 1;

DO $$
DECLARE
  fixture RECORD;
  attending_person UUID;
  tentative_person UUID;
BEGIN
  SELECT * INTO fixture FROM gathering_view_fixture;
  SELECT person.id INTO attending_person FROM public.people person
  WHERE person.organization_id=fixture.organization_id ORDER BY person.created_at LIMIT 1;
  SELECT person.id INTO tentative_person FROM public.people person
  WHERE person.organization_id=fixture.organization_id AND person.id<>attending_person ORDER BY person.created_at LIMIT 1;
  IF fixture.organization_id IS NULL OR attending_person IS NULL OR tentative_person IS NULL THEN
    RAISE EXCEPTION 'Gathering view test requires an admin, linked Circle member, and two People records';
  END IF;

  ALTER TABLE gathering_view_fixture ADD COLUMN attending_person_id UUID;
  ALTER TABLE gathering_view_fixture ADD COLUMN tentative_person_id UUID;
  UPDATE gathering_view_fixture SET attending_person_id=attending_person,tentative_person_id=tentative_person;

  PERFORM set_config('request.jwt.claim.sub',fixture.admin_id::text,true);
  INSERT INTO public.cell_groups(id,organization_id,name,status)
  VALUES(fixture.sibling_group_id,fixture.organization_id,'Read-only gathering fixture','active');
  INSERT INTO public.circle_gatherings(
    id,organization_id,cell_group_id,scope,title,starts_at,ends_at,status,created_by,assignment_confirmed_at
  ) VALUES(
    fixture.gathering_id,fixture.organization_id,fixture.sibling_group_id,'circle','Read-only sibling gathering',
    now()-interval '2 days',now()-interval '2 days'+interval '2 hours','completed',fixture.admin_id,now()
  );
  INSERT INTO public.circle_gathering_rsvps(organization_id,gathering_id,person_id,status)
  VALUES
    (fixture.organization_id,fixture.gathering_id,attending_person,'attending'),
    (fixture.organization_id,fixture.gathering_id,tentative_person,'tentative');
  INSERT INTO public.circle_gathering_reflections(organization_id,gathering_id,author_person_id,body)
  VALUES(fixture.organization_id,fixture.gathering_id,attending_person,'A completed reflection visible across the organization.');
  INSERT INTO public.circle_gathering_reflections(id,organization_id,gathering_id,author_person_id,body)
  VALUES(fixture.viewer_reflection_id,fixture.organization_id,fixture.gathering_id,fixture.viewer_person_id,'A prior reflection from a former participant.');
  INSERT INTO public.circle_guest_rsvps(id,organization_id,gathering_id,guest_name,normalized_contact,status)
  VALUES(fixture.guest_id,fixture.organization_id,fixture.gathering_id,'Private guest fixture','guest-fixture-'||fixture.guest_id,'attending');
  INSERT INTO public.circle_gathering_attendance_records(organization_id,gathering_id,person_id,recorded_by)
  VALUES(fixture.organization_id,fixture.gathering_id,attending_person,fixture.admin_id);
END;
$$;

GRANT SELECT ON gathering_view_fixture TO authenticated;
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  fixture RECORD;
  payload JSONB;
  affected INT;
  rejected BOOLEAN:=false;
  other_admin UUID;
BEGIN
  SELECT * INTO fixture FROM gathering_view_fixture;
  PERFORM set_config('request.jwt.claim.sub',fixture.viewer_id::text,true);

  IF NOT EXISTS(SELECT 1 FROM public.circle_gatherings WHERE id=fixture.gathering_id) THEN
    RAISE EXCEPTION 'Same-organization user cannot view another Circle gathering';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.circle_gathering_reflections WHERE gathering_id=fixture.gathering_id) THEN
    RAISE EXCEPTION 'Same-organization user cannot read completed reflections';
  END IF;
  IF EXISTS(SELECT 1 FROM public.circle_guest_rsvps WHERE gathering_id=fixture.gathering_id)
    OR EXISTS(SELECT 1 FROM public.circle_gathering_attendance_records WHERE gathering_id=fixture.gathering_id) THEN
    RAISE EXCEPTION 'View-only user can read leader-only guest or attendance records';
  END IF;

  UPDATE public.circle_gatherings SET title='Forged edit' WHERE id=fixture.gathering_id;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected<>0 THEN RAISE EXCEPTION 'View-only user updated another Circle gathering'; END IF;

  DELETE FROM public.circle_gathering_reflections WHERE id=fixture.viewer_reflection_id;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected<>0 THEN RAISE EXCEPTION 'View-only user deleted a prior reflection'; END IF;

  BEGIN
    INSERT INTO public.circle_gathering_rsvps(organization_id,gathering_id,person_id,status)
    VALUES(fixture.organization_id,fixture.gathering_id,fixture.viewer_person_id,'attending');
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'View-only user created an RSVP'; END IF;

  rejected:=false;
  BEGIN
    INSERT INTO public.circle_gathering_reflections(organization_id,gathering_id,author_person_id,body)
    VALUES(fixture.organization_id,fixture.gathering_id,fixture.viewer_person_id,'Forged reflection');
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'View-only user created a reflection'; END IF;

  SELECT item INTO payload
  FROM jsonb_array_elements(public.get_circle_dashboard()->'meetings') item
  WHERE item->>'id'=fixture.gathering_id::text;
  IF payload->>'accessLevel'<>'view' THEN RAISE EXCEPTION 'Dashboard did not emit view-only access'; END IF;
  IF NOT (payload->'rsvps' ? fixture.attending_person_id::text)
    OR payload->'rsvps' ? fixture.tentative_person_id::text THEN
    RAISE EXCEPTION 'View-only dashboard payload did not limit RSVPs to confirmed attendees';
  END IF;

  SELECT membership.user_id INTO other_admin
  FROM public.organization_members membership
  WHERE membership.role='admin' AND membership.status='active'
    AND membership.organization_id<>fixture.organization_id
  ORDER BY membership.created_at LIMIT 1;
  IF other_admin IS NULL THEN RAISE EXCEPTION 'Gathering view test requires a second organization admin'; END IF;
  PERFORM set_config('request.jwt.claim.sub',other_admin::text,true);
  IF EXISTS(SELECT 1 FROM public.circle_gatherings WHERE id=fixture.gathering_id) THEN
    RAISE EXCEPTION 'A user from another organization can read the gathering';
  END IF;
END;
$$;

ROLLBACK;
