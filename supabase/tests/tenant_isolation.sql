-- Run against a linked, non-production SheepCount staging database.
-- This suite is intentionally negative: every cross-tenant or over-privileged
-- operation must be invisible or rejected. All attempted writes are rolled back.
BEGIN;

DO $$
BEGIN
  IF has_function_privilege('anon', 'public.submit_circle_guest_rsvp(uuid,text,text,text,text)', 'EXECUTE')
    OR has_function_privilege('anon', 'public.submit_circle_interest(uuid,text,text,text)', 'EXECUTE')
    OR has_function_privilege('anon', 'public.request_circle_connection(uuid,uuid,text,text,text,text,text,boolean)', 'EXECUTE')
    OR has_function_privilege('anon', 'public.submit_circle_group_signup(text,text,text,date,text,text,boolean,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous users can still call a raw public mutation RPC';
  END IF;
END;
$$;

CREATE TEMP TABLE isolation_fixture AS
WITH admins AS (
  SELECT DISTINCT ON (membership.organization_id)
    membership.organization_id,
    membership.user_id
  FROM public.organization_members membership
  WHERE membership.role='admin' AND membership.status='active'
  ORDER BY membership.organization_id, membership.created_at
),
ranked_admins AS (
  SELECT *, row_number() OVER (ORDER BY organization_id) AS position FROM admins
),
linked_people AS (
  SELECT link.organization_id, link.user_id, link.person_id
  FROM public.circle_user_links link
  WHERE link.status='active'
),
leaders AS (
  SELECT DISTINCT ON (group_row.organization_id)
    group_row.organization_id,
    linked.user_id,
    group_row.id AS group_id
  FROM public.cell_groups group_row
  JOIN public.cell_group_members membership ON membership.cell_group_id=group_row.id AND membership.role='Leader'
  JOIN linked_people linked ON linked.organization_id=group_row.organization_id AND linked.person_id=membership.person_id
  WHERE group_row.status='active'
  ORDER BY group_row.organization_id, group_row.created_at
),
members AS (
  SELECT DISTINCT ON (group_row.organization_id)
    group_row.organization_id,
    linked.user_id,
    linked.person_id,
    group_row.id AS group_id
  FROM public.cell_groups group_row
  JOIN public.cell_group_members membership ON membership.cell_group_id=group_row.id AND membership.role<>'Leader'
  JOIN linked_people linked ON linked.organization_id=group_row.organization_id AND linked.person_id=membership.person_id
  WHERE group_row.status='active'
  ORDER BY group_row.organization_id, group_row.created_at
)
SELECT
  first_admin.organization_id AS organization_a,
  first_admin.user_id AS admin_a,
  second_admin.organization_id AS organization_b,
  second_admin.user_id AS admin_b,
  group_a.id AS group_a,
  group_b.id AS group_b,
  leader_a.user_id AS leader_a,
  leader_a.group_id AS leader_group_a,
  member_a.user_id AS member_a,
  member_a.person_id AS member_person_a,
  member_a.group_id AS member_group_a,
  person_b.id AS person_b
FROM ranked_admins first_admin
JOIN ranked_admins second_admin ON second_admin.position=2
JOIN public.cell_groups group_a ON group_a.organization_id=first_admin.organization_id AND group_a.status='active'
JOIN public.cell_groups group_b ON group_b.organization_id=second_admin.organization_id AND group_b.status='active'
LEFT JOIN leaders leader_a ON leader_a.organization_id=first_admin.organization_id
LEFT JOIN members member_a ON member_a.organization_id=first_admin.organization_id
LEFT JOIN LATERAL (
  SELECT id FROM public.people WHERE organization_id=second_admin.organization_id ORDER BY created_at LIMIT 1
) person_b ON true
WHERE first_admin.position=1
ORDER BY group_a.created_at, group_b.created_at
LIMIT 1;

DO $$
DECLARE fixture RECORD;
BEGIN
  SELECT * INTO fixture FROM isolation_fixture;
  IF fixture.organization_a IS NULL OR fixture.organization_b IS NULL OR fixture.group_a IS NULL
    OR fixture.group_b IS NULL OR fixture.leader_a IS NULL OR fixture.member_a IS NULL
    OR fixture.person_b IS NULL THEN
    RAISE EXCEPTION 'Tenant test fixture requires two organizations with admins, active Circles, one linked leader, one linked member, and People records';
  END IF;
END;
$$;

GRANT SELECT ON isolation_fixture TO authenticated;
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  fixture RECORD;
  rejected BOOLEAN;
  before_title TEXT;
BEGIN
  SELECT * INTO fixture FROM isolation_fixture;

  -- An administrator in tenant A cannot read or forge a write into tenant B.
  PERFORM set_config('request.jwt.claim.sub', fixture.admin_a::text, true);
  IF EXISTS (SELECT 1 FROM public.cell_groups WHERE id=fixture.group_b) THEN
    RAISE EXCEPTION 'Tenant A administrator can read a tenant B Circle';
  END IF;
  rejected:=false;
  BEGIN
    INSERT INTO public.circle_announcements(organization_id,cell_group_id,title,body,created_by)
    VALUES(fixture.organization_b,fixture.group_b,'Forged tenant write','Must be rejected',fixture.admin_a);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Tenant A administrator wrote into tenant B'; END IF;

  -- A Circle leader cannot mutate a different Circle by forging its resource ID.
  PERFORM set_config('request.jwt.claim.sub', fixture.leader_a::text, true);
  SELECT title INTO before_title FROM public.circle_gatherings
    WHERE cell_group_id<>fixture.leader_group_a ORDER BY created_at LIMIT 1;
  rejected:=false;
  BEGIN
    PERFORM public.stage_circle_walk_in(
      (SELECT id FROM public.circle_gatherings WHERE cell_group_id<>fixture.leader_group_a ORDER BY created_at LIMIT 1),
      'Forged Visitor','','','either',false
    );
  EXCEPTION WHEN OTHERS THEN
    rejected:=true;
  END;
  IF before_title IS NOT NULL AND NOT rejected THEN
    RAISE EXCEPTION 'Circle leader managed a gathering outside the assigned Circle';
  END IF;

  -- A member can read their Circle but cannot publish leader content.
  PERFORM set_config('request.jwt.claim.sub', fixture.member_a::text, true);
  IF NOT EXISTS (SELECT 1 FROM public.cell_groups WHERE id=fixture.member_group_a) THEN
    RAISE EXCEPTION 'Member cannot read their assigned Circle';
  END IF;
  rejected:=false;
  BEGIN
    INSERT INTO public.circle_announcements(organization_id,cell_group_id,title,body,created_by)
    VALUES(fixture.organization_a,fixture.member_group_a,'Member escalation','Must be rejected',fixture.member_a);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Member published leader-only content'; END IF;

  -- Cross-organization People IDs must be rejected by guarded functions.
  PERFORM set_config('request.jwt.claim.sub', fixture.admin_a::text, true);
  rejected:=false;
  BEGIN
    PERFORM public.add_circle_member(fixture.group_a,fixture.person_b);
  EXCEPTION WHEN OTHERS THEN
    rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Forged cross-tenant Person ID was accepted'; END IF;

  -- A random authenticated identity has no tenant context.
  PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  IF EXISTS (SELECT 1 FROM public.cell_groups WHERE id IN (fixture.group_a,fixture.group_b)) THEN
    RAISE EXCEPTION 'Unlinked authenticated user can read tenant Circles';
  END IF;
END;
$$;

ROLLBACK;
