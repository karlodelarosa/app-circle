-- Self-contained authorization coverage for Circle editing and organization-wide
-- attendance People search. All fixtures and writes are rolled back.
BEGIN;

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
VALUES
  ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','circle-admin-a@example.test','',now(),'{}','{}',now(),now()),
  ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','circle-leader-a@example.test','',now(),'{}','{}',now(),now()),
  ('10000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','circle-member-a@example.test','',now(),'{}','{}',now(),now()),
  ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','circle-admin-b@example.test','',now(),'{}','{}',now(),now());

INSERT INTO public.organizations (id,name,slug,plan,status)
VALUES
  ('10000000-0000-0000-0000-000000000010','Circle Test A','circle-test-a','pro','active'),
  ('20000000-0000-0000-0000-000000000010','Circle Test B','circle-test-b','pro','active'),
  ('30000000-0000-0000-0000-000000000010','Circle Test Without Subscription','circle-test-no-subscription','pro','active');

INSERT INTO public.subscriptions (organization_id,plan,plan_key,status)
VALUES
  ('10000000-0000-0000-0000-000000000010','pro','pro','active'),
  ('20000000-0000-0000-0000-000000000010','pro','pro','active');

INSERT INTO public.organization_members (user_id,organization_id,role,status)
VALUES
  ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000010','admin','active'),
  ('20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000010','admin','active');

ALTER TABLE public.people DISABLE TRIGGER enforce_people_limit_before_insert;
INSERT INTO public.people (
  id,organization_id,first_name,last_name,email,birthdate,status,membership_type,evangelism_stage
)
VALUES
  ('10000000-0000-0000-0000-000000000101','10000000-0000-0000-0000-000000000010','Lina','Leader','lina@example.test','1990-01-01','Active','Member','Small Group'),
  ('10000000-0000-0000-0000-000000000102','10000000-0000-0000-0000-000000000010','Marco','Member','marco@example.test','1991-01-01','Active','Member','Small Group'),
  ('10000000-0000-0000-0000-000000000103','10000000-0000-0000-0000-000000000010','Ina','Inactive','ina@example.test','1992-01-01','Inactive','Member','Small Group'),
  ('10000000-0000-0000-0000-000000000104','10000000-0000-0000-0000-000000000010','Ruth','Organization','ruth@example.test','1994-01-01','Active','Member','Small Group'),
  ('20000000-0000-0000-0000-000000000101','20000000-0000-0000-0000-000000000010','Tessa','Tenant B','tessa@example.test','1993-01-01','Active','Member','Small Group'),
  ('30000000-0000-0000-0000-000000000101','30000000-0000-0000-0000-000000000010','No','Subscription','no-subscription@example.test','1989-01-01','Active','Member','Small Group');
ALTER TABLE public.people ENABLE TRIGGER enforce_people_limit_before_insert;

INSERT INTO public.circle_user_links (organization_id,user_id,person_id,status)
VALUES
  ('10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000101','active'),
  ('10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000102','active');

ALTER TABLE public.cell_groups DISABLE TRIGGER enforce_circle_leader_assignment;
INSERT INTO public.cell_groups (id,organization_id,name,description,location,leader_person_id,status)
VALUES
  ('10000000-0000-0000-0000-000000000201','10000000-0000-0000-0000-000000000010','Circle A','','','10000000-0000-0000-0000-000000000101','active'),
  ('20000000-0000-0000-0000-000000000201','20000000-0000-0000-0000-000000000010','Circle B','','','20000000-0000-0000-0000-000000000101','active'),
  ('30000000-0000-0000-0000-000000000201','30000000-0000-0000-0000-000000000010','Circle Without Subscription','','','30000000-0000-0000-0000-000000000101','active');
ALTER TABLE public.cell_groups ENABLE TRIGGER enforce_circle_leader_assignment;

ALTER TABLE public.cell_group_members DISABLE TRIGGER enforce_cell_leader_training_trigger;
INSERT INTO public.cell_group_members (cell_group_id,person_id,role)
VALUES
  ('10000000-0000-0000-0000-000000000201','10000000-0000-0000-0000-000000000101','Leader'),
  ('10000000-0000-0000-0000-000000000201','10000000-0000-0000-0000-000000000102','Member');
ALTER TABLE public.cell_group_members ENABLE TRIGGER enforce_cell_leader_training_trigger;

INSERT INTO public.circle_gatherings (
  id,organization_id,cell_group_id,title,starts_at,ends_at,created_by,scope,assignment_confirmed_at
)
VALUES
  ('10000000-0000-0000-0000-000000000301','10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000201','Circle A gathering',now()-interval '3 hours',now()-interval '1 hour','10000000-0000-0000-0000-000000000002','circle',now()),
  ('10000000-0000-0000-0000-000000000302','10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000201','Circle A rollback gathering',now()-interval '27 hours',now()-interval '25 hours','10000000-0000-0000-0000-000000000002','circle',now()),
  ('20000000-0000-0000-0000-000000000301','20000000-0000-0000-0000-000000000010','20000000-0000-0000-0000-000000000201','Circle B gathering',now()-interval '3 hours',now()-interval '1 hour','20000000-0000-0000-0000-000000000001','circle',now());

DO $$
DECLARE
  rejected BOOLEAN:=false;
BEGIN
  IF has_function_privilege('authenticated','public.org_people_capacity_available(uuid)','EXECUTE')
    OR has_function_privilege('authenticated','public.org_attendance_capacity_available(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Internal capacity helpers are executable by authenticated users';
  END IF;
  IF public.org_people_capacity_available('30000000-0000-0000-0000-000000000010') IS NOT NULL
    OR public.org_attendance_capacity_available('30000000-0000-0000-0000-000000000010') IS NOT NULL THEN
    RAISE EXCEPTION 'Missing subscription unexpectedly resolved capacity';
  END IF;
  BEGIN
    INSERT INTO public.people(
      organization_id,first_name,last_name,email,birthdate,status,membership_type,evangelism_stage
    ) VALUES(
      '30000000-0000-0000-0000-000000000010','Missing','Subscription','missing-subscription@example.test',
      '1990-01-01','Active','Member','Small Group'
    );
  EXCEPTION WHEN OTHERS THEN
    rejected:=SQLERRM='Organization subscription is not configured';
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Missing subscription did not fail closed with the configuration error'; END IF;
  rejected:=false;
  BEGIN
    INSERT INTO public.cell_group_sessions(
      organization_id,cell_group_id,session_date,leader_person_id,leader_name,location
    ) VALUES(
      '30000000-0000-0000-0000-000000000010','30000000-0000-0000-0000-000000000201',
      current_date,'30000000-0000-0000-0000-000000000101','No Subscription',''
    );
  EXCEPTION WHEN OTHERS THEN
    rejected:=SQLERRM='Organization subscription is not configured';
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Missing subscription did not block an attendance session'; END IF;
END;
$$;

SET LOCAL ROLE authenticated;

DO $$
DECLARE
  results JSONB;
  rejected BOOLEAN;
  affected_rows INT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
  IF public.org_can_add_person('10000000-0000-0000-0000-000000000010')
    OR public.org_can_add_attendance_session('10000000-0000-0000-0000-000000000010') THEN
    RAISE EXCEPTION 'Caller-aware entitlement checks exposed organization capacity to a Circle-only leader';
  END IF;
  results:=public.search_circle_attendance_people('10000000-0000-0000-0000-000000000301','marco');
  IF NOT results @> '[{"id":"10000000-0000-0000-0000-000000000102"}]'::jsonb THEN
    RAISE EXCEPTION 'Assigned leader could not find an active organization Person';
  END IF;
  results:=public.search_circle_attendance_people('10000000-0000-0000-0000-000000000301','ina inactive');
  IF results <> '[]'::jsonb THEN RAISE EXCEPTION 'Inactive Person appeared in attendance search'; END IF;
  results:=public.search_circle_attendance_people('10000000-0000-0000-0000-000000000301','tessa');
  IF results <> '[]'::jsonb THEN RAISE EXCEPTION 'Cross-tenant Person appeared in attendance search'; END IF;

  results:=public.search_circle_attendance_people('10000000-0000-0000-0000-000000000301','ruth');
  IF NOT results @> '[{"id":"10000000-0000-0000-0000-000000000104"}]'::jsonb THEN
    RAISE EXCEPTION 'Leader could not find a non-Circle organization Person';
  END IF;
  results:=public.save_circle_gathering_closeout(
    '10000000-0000-0000-0000-000000000301',
    ARRAY['10000000-0000-0000-0000-000000000104'::uuid],
    ARRAY[]::uuid[],
    '[{"firstName":"Nora","lastName":"Newcomer","birthdate":"1995-05-15"}]'::jsonb,
    '',
    false
  );
  IF NOT results->'personIds' @> '["10000000-0000-0000-0000-000000000104"]'::jsonb THEN
    RAISE EXCEPTION 'External organization Person was not saved as attended';
  END IF;
  results:=public.get_circle_gathering_attendance('10000000-0000-0000-0000-000000000301');
  IF NOT results->'attendees' @> '[{"personId":"10000000-0000-0000-0000-000000000104","fullName":"Ruth Organization"}]'::jsonb THEN
    RAISE EXCEPTION 'Saved external attendee was not returned when reopening the closeout';
  END IF;
  IF NOT results->'attendees' @> '[{"fullName":"Nora Newcomer","isProspect":true}]'::jsonb THEN
    RAISE EXCEPTION 'Circle-only leader could not save a newcomer while capacity remained';
  END IF;
  IF (SELECT count(*) FROM public.cell_group_members WHERE cell_group_id='10000000-0000-0000-0000-000000000201')<>2 THEN
    RAISE EXCEPTION 'Recording attendance changed Circle membership';
  END IF;

  UPDATE public.cell_groups SET location='Updated location'
  WHERE id='10000000-0000-0000-0000-000000000201';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows<>1 THEN RAISE EXCEPTION 'Assigned leader could not edit Circle details'; END IF;

  rejected:=false;
  BEGIN
    PERFORM public.search_circle_attendance_people('20000000-0000-0000-0000-000000000301','tessa');
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Leader searched a cross-tenant gathering'; END IF;
  rejected:=false;
  BEGIN
    PERFORM public.save_circle_gathering_closeout(
      '20000000-0000-0000-0000-000000000301',ARRAY[]::uuid[],ARRAY[]::uuid[],'[]'::jsonb,'',false
    );
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Leader closed out a cross-tenant gathering'; END IF;
  UPDATE public.cell_groups SET location='Cross-tenant forged location'
  WHERE id='20000000-0000-0000-0000-000000000201';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows<>0 THEN RAISE EXCEPTION 'Unrelated leader edited a cross-tenant Circle'; END IF;

  rejected:=false;
  BEGIN
    PERFORM public.search_circle_attendance_people('10000000-0000-0000-0000-000000000301','r');
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Attendance search accepted a short query'; END IF;

  PERFORM set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
  rejected:=false;
  BEGIN
    PERFORM public.search_circle_attendance_people('10000000-0000-0000-0000-000000000301','marco');
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Ordinary member searched gathering attendance People'; END IF;
  rejected:=false;
  BEGIN
    PERFORM public.save_circle_gathering_closeout(
      '10000000-0000-0000-0000-000000000301',ARRAY[]::uuid[],ARRAY[]::uuid[],'[]'::jsonb,'',false
    );
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Ordinary member closed out a gathering'; END IF;
  UPDATE public.cell_groups SET location='Forged location'
  WHERE id='10000000-0000-0000-0000-000000000201';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows<>0 THEN RAISE EXCEPTION 'Ordinary member edited Circle details'; END IF;

  PERFORM set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
  results:=public.search_circle_attendance_people('10000000-0000-0000-0000-000000000301','lina');
  IF jsonb_array_length(results)<>1 THEN RAISE EXCEPTION 'Organization admin could not search attendance People'; END IF;
  IF NOT public.org_can_add_person('10000000-0000-0000-0000-000000000010')
    OR NOT public.org_can_add_attendance_session('10000000-0000-0000-0000-000000000010') THEN
    RAISE EXCEPTION 'Organization admin could not read available subscription capacity';
  END IF;

  PERFORM set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000001',true);
  UPDATE public.cell_groups SET location='Admin updated location'
  WHERE id='20000000-0000-0000-0000-000000000201';
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows<>1 THEN RAISE EXCEPTION 'Organization admin could not edit Circle details'; END IF;
END;
$$;

RESET ROLE;

UPDATE public.subscriptions
SET override_max_people=public.get_org_people_count(organization_id)
WHERE organization_id='10000000-0000-0000-0000-000000000010';
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  rejected BOOLEAN:=false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
  BEGIN
    PERFORM public.save_circle_gathering_closeout(
      '10000000-0000-0000-0000-000000000301',ARRAY[]::uuid[],ARRAY[]::uuid[],
      '[{"firstName":"People","lastName":"At Limit","birthdate":"1996-06-16"}]'::jsonb,'',false
    );
  EXCEPTION WHEN OTHERS THEN
    rejected:=SQLERRM='People limit reached for this organization';
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Actual People limit was not enforced with the expected error'; END IF;
END;
$$;

RESET ROLE;
UPDATE public.subscriptions
SET override_max_people=NULL,
    override_max_attendance_sessions=public.get_org_attendance_session_count(organization_id)
WHERE organization_id='10000000-0000-0000-0000-000000000010';
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  rejected BOOLEAN:=false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
  BEGIN
    PERFORM public.save_circle_gathering_closeout(
      '10000000-0000-0000-0000-000000000302',ARRAY[]::uuid[],ARRAY[]::uuid[],
      '[{"firstName":"Rolled","lastName":"Back","birthdate":"1997-07-17"}]'::jsonb,'',false
    );
  EXCEPTION WHEN OTHERS THEN
    rejected:=SQLERRM='Attendance session limit reached for this organization';
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Actual attendance-session limit was not enforced with the expected error'; END IF;
  IF EXISTS(
    SELECT 1 FROM public.people
    WHERE organization_id='10000000-0000-0000-0000-000000000010'
      AND first_name='Rolled' AND last_name='Back'
  ) THEN
    RAISE EXCEPTION 'Failed closeout left a partially created newcomer';
  END IF;
END;
$$;

RESET ROLE;
ROLLBACK;
