-- Run against a linked, non-production SheepCount staging database.
-- Verifies that the member-insert policy no longer reads RLS-protected people
-- directly and therefore cannot recurse through the people visibility policy.
BEGIN;

DO $$
DECLARE
  policy_expression TEXT;
  helper_security_definer BOOLEAN;
BEGIN
  SELECT pg_get_expr(policy.polwithcheck, policy.polrelid)
  INTO policy_expression
  FROM pg_policy policy
  JOIN pg_class relation ON relation.oid = policy.polrelid
  JOIN pg_namespace schema_name ON schema_name.oid = relation.relnamespace
  WHERE schema_name.nspname = 'public'
    AND relation.relname = 'cell_group_members'
    AND policy.polname = 'Circle leaders add group members';

  IF policy_expression IS NULL THEN
    RAISE EXCEPTION 'Cell group member insert policy is missing';
  END IF;

  IF policy_expression NOT ILIKE '%circle_can_add_group_member%' THEN
    RAISE EXCEPTION 'Insert policy does not use the non-recursive authorization helper: %', policy_expression;
  END IF;

  IF policy_expression ILIKE '%people%' THEN
    RAISE EXCEPTION 'Insert policy still reads the RLS-protected people table directly: %', policy_expression;
  END IF;

  SELECT procedure.prosecdef
  INTO helper_security_definer
  FROM pg_proc procedure
  JOIN pg_namespace schema_name ON schema_name.oid = procedure.pronamespace
  WHERE schema_name.nspname = 'public'
    AND procedure.proname = 'circle_can_add_group_member'
    AND pg_get_function_identity_arguments(procedure.oid) = 'p_cell_group_id uuid, p_person_id uuid';

  IF helper_security_definer IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'circle_can_add_group_member must remain SECURITY DEFINER';
  END IF;
END;
$$;

ROLLBACK;
