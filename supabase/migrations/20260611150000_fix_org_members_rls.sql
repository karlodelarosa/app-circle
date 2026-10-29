-- organization_members SELECT returned 403 because "Members can view org membership"
-- self-referenced organization_members in RLS (infinite recursion).
-- Own membership is already allowed by "Users can view own memberships".

DROP POLICY IF EXISTS "Members can view org membership" ON public.organization_members;
-- Stale policy still calling revoked is_org_member()
DROP POLICY IF EXISTS "Org members can delete people" ON public.people;
