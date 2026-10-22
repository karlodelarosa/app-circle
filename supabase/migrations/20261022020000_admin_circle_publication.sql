BEGIN;

DROP POLICY IF EXISTS "Leaders manage Circle listings" ON public.circle_public_listings;
DROP POLICY IF EXISTS "Org admins manage Circle listings" ON public.circle_public_listings;

CREATE POLICY "Org admins manage Circle listings"
  ON public.circle_public_listings
  FOR ALL
  TO authenticated
  USING (public.circle_is_org_admin(organization_id))
  WITH CHECK (public.circle_is_org_admin(organization_id));

COMMIT;
