-- Self-contained authorization and activity-guard coverage for permanent
-- gathering deletion. All fixtures and writes are rolled back.
BEGIN;

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
VALUES
  ('31000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','delete-admin@example.test','',now(),'{}','{}',now(),now()),
  ('31000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','delete-leader@example.test','',now(),'{}','{}',now(),now()),
  ('31000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','delete-member@example.test','',now(),'{}','{}',now(),now()),
  ('32000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','delete-outsider@example.test','',now(),'{}','{}',now(),now());

INSERT INTO public.organizations (id,name,slug,plan,status)
VALUES
  ('31000000-0000-0000-0000-000000000010','Delete Test A','delete-test-a','pro','active'),
  ('32000000-0000-0000-0000-000000000010','Delete Test B','delete-test-b','pro','active');
INSERT INTO public.subscriptions (organization_id,plan,plan_key,status)
VALUES
  ('31000000-0000-0000-0000-000000000010','pro','pro','active'),
  ('32000000-0000-0000-0000-000000000010','pro','pro','active');
INSERT INTO public.organization_members (user_id,organization_id,role,status)
VALUES
  ('31000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000010','admin','active'),
  ('32000000-0000-0000-0000-000000000001','32000000-0000-0000-0000-000000000010','admin','active');

ALTER TABLE public.people DISABLE TRIGGER enforce_people_limit_before_insert;
INSERT INTO public.people (
  id,organization_id,first_name,last_name,email,birthdate,status,membership_type,evangelism_stage
)
VALUES
  ('31000000-0000-0000-0000-000000000101','31000000-0000-0000-0000-000000000010','Delete','Leader','delete-leader@example.test','1990-01-01','Active','Member','Small Group'),
  ('31000000-0000-0000-0000-000000000102','31000000-0000-0000-0000-000000000010','Delete','Member','delete-member@example.test','1991-01-01','Active','Member','Small Group');
ALTER TABLE public.people ENABLE TRIGGER enforce_people_limit_before_insert;

INSERT INTO public.circle_user_links (organization_id,user_id,person_id,status)
VALUES
  ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000002','31000000-0000-0000-0000-000000000101','active'),
  ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000003','31000000-0000-0000-0000-000000000102','active');
ALTER TABLE public.cell_groups DISABLE TRIGGER enforce_circle_leader_assignment;
INSERT INTO public.cell_groups (id,organization_id,name,description,location,leader_person_id,status)
VALUES ('31000000-0000-0000-0000-000000000201','31000000-0000-0000-0000-000000000010','Delete Circle','','','31000000-0000-0000-0000-000000000101','active');
ALTER TABLE public.cell_groups ENABLE TRIGGER enforce_circle_leader_assignment;
ALTER TABLE public.cell_group_members DISABLE TRIGGER enforce_cell_leader_training_trigger;
INSERT INTO public.cell_group_members (cell_group_id,person_id,role)
VALUES
  ('31000000-0000-0000-0000-000000000201','31000000-0000-0000-0000-000000000101','Leader'),
  ('31000000-0000-0000-0000-000000000201','31000000-0000-0000-0000-000000000102','Member');
ALTER TABLE public.cell_group_members ENABLE TRIGGER enforce_cell_leader_training_trigger;

-- 301 and 302 are empty Circle and organization gatherings. 303 and 304
-- remain empty for authorization failures. 310-317 each carry one distinct
-- kind of protected activity.
INSERT INTO public.circle_gatherings (
  id,organization_id,cell_group_id,title,starts_at,ends_at,status,created_by,scope,assignment_confirmed_at
)
SELECT
  id,
  '31000000-0000-0000-0000-000000000010'::uuid,
  CASE WHEN id='31000000-0000-0000-0000-000000000302'::uuid THEN NULL ELSE '31000000-0000-0000-0000-000000000201'::uuid END,
  title, now()-interval '3 hours', now()-interval '1 hour', status,
  '31000000-0000-0000-0000-000000000002'::uuid,
  CASE WHEN id='31000000-0000-0000-0000-000000000302'::uuid THEN 'organization' ELSE 'circle' END,
  now()
FROM (VALUES
  ('31000000-0000-0000-0000-000000000301'::uuid,'Empty Circle','scheduled'),
  ('31000000-0000-0000-0000-000000000302'::uuid,'Empty Organization','scheduled'),
  ('31000000-0000-0000-0000-000000000303'::uuid,'Member denied','scheduled'),
  ('31000000-0000-0000-0000-000000000304'::uuid,'Outsider denied','scheduled'),
  ('31000000-0000-0000-0000-000000000310'::uuid,'Member RSVP','scheduled'),
  ('31000000-0000-0000-0000-000000000311'::uuid,'Guest RSVP','scheduled'),
  ('31000000-0000-0000-0000-000000000312'::uuid,'Check-in opened','scheduled'),
  ('31000000-0000-0000-0000-000000000313'::uuid,'Attendance session','scheduled'),
  ('31000000-0000-0000-0000-000000000314'::uuid,'Attendance record','scheduled'),
  ('31000000-0000-0000-0000-000000000315'::uuid,'Closeout','scheduled'),
  ('31000000-0000-0000-0000-000000000316'::uuid,'Reflection','completed'),
  ('31000000-0000-0000-0000-000000000317'::uuid,'Gallery','scheduled')
) fixture(id,title,status);

INSERT INTO public.circle_gathering_rsvps (organization_id,gathering_id,person_id,status)
VALUES ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000310','31000000-0000-0000-0000-000000000102','attending');
INSERT INTO public.circle_guest_rsvps (organization_id,gathering_id,guest_name,normalized_contact,status)
VALUES ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000311','Guest Person','guest@example.test','attending');
UPDATE public.circle_gatherings SET checkin_opened_at=now()
WHERE id='31000000-0000-0000-0000-000000000312';
ALTER TABLE public.cell_group_sessions DISABLE TRIGGER enforce_cell_group_attendance_session_limit;
INSERT INTO public.cell_group_sessions (
  id,organization_id,cell_group_id,session_date,leader_person_id,leader_name,location
)
VALUES ('31000000-0000-0000-0000-000000000401','31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000201',current_date-1,'31000000-0000-0000-0000-000000000101','Delete Leader','Test');
ALTER TABLE public.cell_group_sessions ENABLE TRIGGER enforce_cell_group_attendance_session_limit;
UPDATE public.circle_gatherings SET attendance_session_id='31000000-0000-0000-0000-000000000401'
WHERE id='31000000-0000-0000-0000-000000000313';
INSERT INTO public.circle_gathering_attendance_records (
  organization_id,gathering_id,person_id,recorded_by
)
VALUES ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000314','31000000-0000-0000-0000-000000000102','31000000-0000-0000-0000-000000000002');
INSERT INTO public.circle_gathering_closeouts (gathering_id,organization_id,updated_by)
VALUES ('31000000-0000-0000-0000-000000000315','31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000002');
INSERT INTO public.circle_gathering_reflections (
  organization_id,gathering_id,author_person_id,body
)
VALUES ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000316','31000000-0000-0000-0000-000000000102','Protected reflection');
INSERT INTO public.circle_galleries (
  organization_id,gathering_id,cell_group_id,public_slug,title,created_by,assignment_confirmed_at
)
VALUES ('31000000-0000-0000-0000-000000000010','31000000-0000-0000-0000-000000000317','31000000-0000-0000-0000-000000000201','delete-protected-gallery','Protected gallery','31000000-0000-0000-0000-000000000002',now());

SET LOCAL ROLE authenticated;
DO $$
DECLARE
  result JSONB;
  target UUID;
  rejected BOOLEAN;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000003',true);
  rejected:=false;
  BEGIN
    PERFORM public.delete_empty_circle_gathering('31000000-0000-0000-0000-000000000303');
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected OR NOT EXISTS(SELECT 1 FROM public.circle_gatherings WHERE id='31000000-0000-0000-0000-000000000303') THEN
    RAISE EXCEPTION 'Ordinary member deleted an empty gathering';
  END IF;

  PERFORM set_config('request.jwt.claim.sub','32000000-0000-0000-0000-000000000001',true);
  rejected:=false;
  BEGIN
    PERFORM public.delete_empty_circle_gathering('31000000-0000-0000-0000-000000000304');
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected OR NOT EXISTS(SELECT 1 FROM public.circle_gatherings WHERE id='31000000-0000-0000-0000-000000000304') THEN
    RAISE EXCEPTION 'Unrelated organization admin deleted an empty gathering';
  END IF;

  PERFORM set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000002',true);
  result:=public.delete_empty_circle_gathering('31000000-0000-0000-0000-000000000301');
  IF result <> '{"deleted":true}'::jsonb OR EXISTS(SELECT 1 FROM public.circle_gatherings WHERE id='31000000-0000-0000-0000-000000000301') THEN
    RAISE EXCEPTION 'Circle leader could not delete an empty Circle gathering: %',result;
  END IF;
  result:=public.delete_empty_circle_gathering('31000000-0000-0000-0000-000000000302');
  IF result <> '{"deleted":true}'::jsonb OR EXISTS(SELECT 1 FROM public.circle_gatherings WHERE id='31000000-0000-0000-0000-000000000302') THEN
    RAISE EXCEPTION 'Organization gathering creator could not delete an empty gathering: %',result;
  END IF;

  FOREACH target IN ARRAY ARRAY[
    '31000000-0000-0000-0000-000000000310'::uuid,
    '31000000-0000-0000-0000-000000000311'::uuid,
    '31000000-0000-0000-0000-000000000312'::uuid,
    '31000000-0000-0000-0000-000000000313'::uuid,
    '31000000-0000-0000-0000-000000000314'::uuid,
    '31000000-0000-0000-0000-000000000315'::uuid,
    '31000000-0000-0000-0000-000000000316'::uuid,
    '31000000-0000-0000-0000-000000000317'::uuid
  ] LOOP
    result:=public.delete_empty_circle_gathering(target);
    IF result <> '{"deleted":false,"reason":"has_activity"}'::jsonb
      OR NOT EXISTS(SELECT 1 FROM public.circle_gatherings WHERE id=target) THEN
      RAISE EXCEPTION 'Protected gathering % was removed or returned an unstable result: %',target,result;
    END IF;
  END LOOP;

  IF NOT EXISTS(SELECT 1 FROM public.circle_gathering_rsvps WHERE gathering_id='31000000-0000-0000-0000-000000000310')
    OR NOT EXISTS(SELECT 1 FROM public.circle_guest_rsvps WHERE gathering_id='31000000-0000-0000-0000-000000000311')
    OR NOT EXISTS(SELECT 1 FROM public.circle_gathering_attendance_records WHERE gathering_id='31000000-0000-0000-0000-000000000314')
    OR NOT EXISTS(SELECT 1 FROM public.circle_gathering_closeouts WHERE gathering_id='31000000-0000-0000-0000-000000000315')
    OR NOT EXISTS(SELECT 1 FROM public.circle_gathering_reflections WHERE gathering_id='31000000-0000-0000-0000-000000000316')
    OR NOT EXISTS(SELECT 1 FROM public.circle_galleries WHERE gathering_id='31000000-0000-0000-0000-000000000317') THEN
    RAISE EXCEPTION 'A blocked deletion changed linked activity';
  END IF;
END;
$$;
RESET ROLE;
ROLLBACK;
