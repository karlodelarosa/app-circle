-- Allow gathering managers to permanently remove mistakes only while no
-- participation, closeout, reflection, check-in, or gallery history exists.

CREATE OR REPLACE FUNCTION public.delete_empty_circle_gathering(
  p_gathering_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  gathering public.circle_gatherings%ROWTYPE;
BEGIN
  SELECT *
  INTO gathering
  FROM public.circle_gatherings
  WHERE id = p_gathering_id
  FOR UPDATE;

  IF gathering.id IS NULL THEN
    RAISE EXCEPTION 'Gathering not found';
  END IF;

  IF NOT public.circle_can_manage_gathering(gathering.id) THEN
    RAISE EXCEPTION 'Gathering manager access required';
  END IF;

  IF gathering.attendance_session_id IS NOT NULL
    OR gathering.checkin_opened_at IS NOT NULL
    OR EXISTS (
      SELECT 1 FROM public.circle_gathering_rsvps
      WHERE gathering_id = gathering.id
    )
    OR EXISTS (
      SELECT 1 FROM public.circle_guest_rsvps
      WHERE gathering_id = gathering.id
    )
    OR EXISTS (
      SELECT 1 FROM public.circle_gathering_attendance_records
      WHERE gathering_id = gathering.id
    )
    OR EXISTS (
      SELECT 1 FROM public.circle_gathering_closeouts
      WHERE gathering_id = gathering.id
    )
    OR EXISTS (
      SELECT 1 FROM public.circle_gathering_reflections
      WHERE gathering_id = gathering.id
    )
    OR EXISTS (
      SELECT 1 FROM public.circle_galleries
      WHERE gathering_id = gathering.id
    )
  THEN
    RETURN jsonb_build_object('deleted', false, 'reason', 'has_activity');
  END IF;

  DELETE FROM public.circle_gatherings WHERE id = gathering.id;
  RETURN jsonb_build_object('deleted', true);
END;
$$;

REVOKE ALL ON FUNCTION public.delete_empty_circle_gathering(UUID)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_empty_circle_gathering(UUID)
  TO authenticated;
