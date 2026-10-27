BEGIN;
-- Organization gatherings are returned by the secured dashboard RPC, but the
-- table policy still only exposed gatherings with a Circle destination. RSVP
-- INSERT checks must be able to read the matching gathering row.
DROP POLICY IF EXISTS "Circle members read gatherings" ON public.circle_gatherings;
CREATE POLICY "Members read accessible gatherings"
ON public.circle_gatherings FOR SELECT TO authenticated
USING (public.circle_can_access_gathering(id));
COMMIT;
