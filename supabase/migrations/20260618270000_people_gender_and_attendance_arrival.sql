CREATE TYPE public.person_gender AS ENUM ('Male', 'Female');
ALTER TABLE public.people
  ADD COLUMN gender public.person_gender;
ALTER TABLE public.service_session_attendees
  ADD COLUMN time_of_arrival TIME;
CREATE POLICY "Org members can update session attendees"
  ON public.service_session_attendees FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.service_sessions ss
      JOIN public.organization_members om ON om.organization_id = ss.organization_id
      WHERE ss.id = service_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.service_sessions ss
      JOIN public.organization_members om ON om.organization_id = ss.organization_id
      WHERE ss.id = service_session_attendees.session_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
