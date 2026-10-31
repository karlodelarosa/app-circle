-- Run against a linked, non-production SheepCount staging database.
-- Exercises organization-scoped leadership approval without creating a group.
BEGIN;

DO $$
DECLARE
  admin_user UUID;
  admin_org UUID;
  candidate UUID;
  foreign_person UUID;
  group_count_before BIGINT;
  group_count_after BIGINT;
  approval_events_before BIGINT;
  approval_events_after BIGINT;
  result JSONB;
BEGIN
  SELECT membership.user_id, membership.organization_id
  INTO admin_user, admin_org
  FROM public.organization_members membership
  WHERE membership.role = 'admin' AND membership.status = 'active'
  ORDER BY membership.created_at
  LIMIT 1;

  SELECT person.id INTO candidate
  FROM public.people person
  WHERE person.organization_id = admin_org
    AND person.status = 'Active'
    AND NOT EXISTS (
      SELECT 1 FROM public.circle_leader_approvals approval
      WHERE approval.organization_id = admin_org
        AND approval.person_id = person.id
        AND approval.status = 'approved'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.cell_groups group_row
      LEFT JOIN public.cell_group_members group_membership
        ON group_membership.cell_group_id = group_row.id
        AND group_membership.person_id = person.id
        AND group_membership.role = 'Leader'
      WHERE group_row.organization_id = admin_org
        AND group_row.status = 'active'
        AND (group_row.leader_person_id = person.id OR group_membership.id IS NOT NULL)
    )
  ORDER BY person.created_at
  LIMIT 1;

  IF admin_user IS NULL OR candidate IS NULL THEN
    RAISE EXCEPTION 'Leader approval test requires an admin and active person';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', admin_user::text, true);
  SELECT count(*) INTO group_count_before FROM public.cell_groups WHERE organization_id = admin_org;
  SELECT count(*) INTO approval_events_before
  FROM public.circle_account_transitions transition
  WHERE transition.organization_id = admin_org
    AND transition.person_id = candidate
    AND transition.action = 'leadership_approved';

  SELECT public.set_cell_group_leader_approvals(admin_org, ARRAY[candidate], true) INTO result;
  IF COALESCE((result->0->>'ok')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Active same-tenant person was not approved: %', result;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.circle_leader_approvals approval
    WHERE approval.organization_id = admin_org
      AND approval.person_id = candidate
      AND approval.status = 'approved'
  ) THEN
    RAISE EXCEPTION 'Approved leader predicate did not recognize the candidate';
  END IF;

  SELECT count(*) INTO group_count_after FROM public.cell_groups WHERE organization_id = admin_org;
  IF group_count_after <> group_count_before THEN
    RAISE EXCEPTION 'Approving a leader created a cell group';
  END IF;

  SELECT count(*) INTO approval_events_after
  FROM public.circle_account_transitions transition
  WHERE transition.organization_id = admin_org
    AND transition.person_id = candidate
    AND transition.action = 'leadership_approved';
  IF approval_events_after <> approval_events_before + 1 THEN
    RAISE EXCEPTION 'Approval did not create exactly one audit transition';
  END IF;

  IF COALESCE((
    SELECT (entry->>'activeGroupCount')::integer
    FROM jsonb_array_elements(public.get_cell_group_leadership_roster(admin_org)) entry
    WHERE entry->>'personId' = candidate::text
  ), -1) <> 0 THEN
    RAISE EXCEPTION 'Approved ungrouped leader was not classified with zero active groups';
  END IF;

  SELECT public.set_cell_group_leader_approvals(admin_org, ARRAY[candidate], true) INTO result;
  IF COALESCE((result->0->>'ok')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Repeated approval was not idempotent: %', result;
  END IF;
  SELECT count(*) INTO approval_events_after
  FROM public.circle_account_transitions transition
  WHERE transition.organization_id = admin_org
    AND transition.person_id = candidate
    AND transition.action = 'leadership_approved';
  IF approval_events_after <> approval_events_before + 1 THEN
    RAISE EXCEPTION 'Idempotent approval created a duplicate audit transition';
  END IF;

  SELECT public.set_cell_group_leader_approvals(admin_org, ARRAY[candidate], false) INTO result;
  IF COALESCE((result->0->>'ok')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Ungrouped leader could not be revoked: %', result;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.circle_account_transitions transition
    WHERE transition.organization_id = admin_org
      AND transition.person_id = candidate
      AND transition.action = 'leadership_revoked'
  ) THEN
    RAISE EXCEPTION 'Revocation audit transition was not recorded';
  END IF;

  SELECT person.id INTO foreign_person
  FROM public.people person
  WHERE person.organization_id <> admin_org AND person.status = 'Active'
  LIMIT 1;
  IF foreign_person IS NOT NULL THEN
    SELECT public.set_cell_group_leader_approvals(admin_org, ARRAY[foreign_person], true) INTO result;
    IF COALESCE((result->0->>'ok')::boolean, true) IS NOT FALSE THEN
      RAISE EXCEPTION 'A foreign-tenant person was approved: %', result;
    END IF;
  END IF;

  UPDATE public.people SET status = 'Inactive' WHERE id = candidate;
  SELECT public.set_cell_group_leader_approvals(admin_org, ARRAY[candidate], true) INTO result;
  IF COALESCE((result->0->>'ok')::boolean, true) IS NOT FALSE THEN
    RAISE EXCEPTION 'An inactive person was approved: %', result;
  END IF;
END;
$$;

ROLLBACK;
