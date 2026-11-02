BEGIN;

-- Keep every table read needed by the INSERT policy behind one security-definer
-- boundary. Reading public.people directly from the policy recursively invokes
-- its Circle visibility policy, which reads public.cell_group_members again.
CREATE OR REPLACE FUNCTION public.circle_can_add_group_member(
  p_cell_group_id UUID,
  p_person_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    public.circle_can_lead_group(p_cell_group_id)
    AND EXISTS (
      SELECT 1
      FROM public.cell_groups group_row
      JOIN public.people person
        ON person.organization_id = group_row.organization_id
      WHERE group_row.id = p_cell_group_id
        AND person.id = p_person_id
    );
$$;

REVOKE ALL ON FUNCTION public.circle_can_add_group_member(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.circle_can_add_group_member(UUID, UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.circle_can_add_group_member(UUID, UUID) TO authenticated;

COMMENT ON FUNCTION public.circle_can_add_group_member(UUID, UUID) IS
  'Checks group leadership and tenant membership without recursively evaluating table RLS policies.';

DROP POLICY IF EXISTS "Circle leaders add group members" ON public.cell_group_members;
CREATE POLICY "Circle leaders add group members"
  ON public.cell_group_members
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.circle_can_add_group_member(cell_group_id, person_id)
  );

COMMIT;
