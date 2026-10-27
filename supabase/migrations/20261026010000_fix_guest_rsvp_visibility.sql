BEGIN;
DROP POLICY IF EXISTS "Leaders read guest RSVPs" ON public.circle_guest_rsvps;
DROP POLICY IF EXISTS "Gathering managers read guest RSVPs" ON public.circle_guest_rsvps;
CREATE POLICY "Gathering managers read guest RSVPs"
ON public.circle_guest_rsvps FOR SELECT TO authenticated
USING (public.circle_can_manage_gathering(gathering_id));
COMMIT;
