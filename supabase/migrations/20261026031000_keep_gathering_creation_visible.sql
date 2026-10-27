BEGIN;
-- Keep the access decision row-local. A STABLE helper that re-queries the
-- gathering cannot see that same row during INSERT ... RETURNING.
DROP POLICY IF EXISTS "Members read accessible gatherings" ON public.circle_gatherings;
CREATE POLICY "Members read accessible gatherings"
ON public.circle_gatherings FOR SELECT TO authenticated
USING (
  (scope='circle' AND public.circle_can_access_group(cell_group_id))
  OR
  (scope='organization' AND EXISTS (
    SELECT 1 FROM public.organization_members membership
    WHERE membership.organization_id=circle_gatherings.organization_id
      AND membership.user_id=auth.uid()
      AND membership.status='active'
  ))
);
COMMIT;
