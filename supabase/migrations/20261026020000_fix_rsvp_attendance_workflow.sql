BEGIN;
ALTER TABLE public.circle_gatherings
ADD COLUMN IF NOT EXISTS attendance_saved_at TIMESTAMPTZ;
UPDATE public.circle_gatherings gathering
SET attendance_saved_at=COALESCE(gathering.updated_at,now())
WHERE gathering.attendance_saved_at IS NULL
  AND (
    gathering.attendance_session_id IS NOT NULL
    OR EXISTS(
      SELECT 1 FROM public.circle_gathering_attendance_records record
      WHERE record.gathering_id=gathering.id
    )
    OR EXISTS(
      SELECT 1 FROM public.circle_guest_rsvps rsvp
      WHERE rsvp.gathering_id=gathering.id AND rsvp.attended_at IS NOT NULL
    )
  );
-- An authenticated upsert needs SELECT visibility on the conflicting row
-- before PostgreSQL can apply the UPDATE branch.
DROP POLICY IF EXISTS "Members read own gathering RSVP" ON public.circle_gathering_rsvps;
CREATE POLICY "Members read own gathering RSVP"
ON public.circle_gathering_rsvps FOR SELECT TO authenticated
USING (person_id = public.circle_current_person_id(organization_id));
DROP POLICY IF EXISTS "Gathering managers read member RSVPs" ON public.circle_gathering_rsvps;
CREATE POLICY "Gathering managers read member RSVPs"
ON public.circle_gathering_rsvps FOR SELECT TO authenticated
USING (public.circle_can_manage_gathering(gathering_id));
-- Saving a roster and completing a gathering are separate actions. The old
-- implementation completed every gathering as a side effect of roster saves.
CREATE OR REPLACE FUNCTION public.record_circle_attendance(
  p_gathering_id UUID,
  p_person_ids UUID[],
  p_guest_rsvp_ids UUID[] DEFAULT ARRAY[]::UUID[]
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  gathering public.circle_gatherings%ROWTYPE;
  group_row public.cell_groups%ROWTYPE;
  v_session_id UUID;
  leader_name TEXT;
  record_id UUID;
BEGIN
  SELECT * INTO gathering FROM public.circle_gatherings WHERE id=p_gathering_id;
  IF gathering.id IS NULL OR NOT public.circle_can_manage_gathering(gathering.id) THEN
    RAISE EXCEPTION 'Gathering manager access required';
  END IF;

  IF gathering.scope='organization' THEN
    IF EXISTS(
      SELECT 1 FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id
      WHERE NOT EXISTS(
        SELECT 1 FROM public.people person
        WHERE person.id=attendee_person_id
          AND person.organization_id=gathering.organization_id
          AND lower(person.status)='active'
          AND EXISTS(
            SELECT 1
            FROM public.cell_group_members membership
            JOIN public.cell_groups group_check ON group_check.id=membership.cell_group_id
            WHERE membership.person_id=person.id
              AND group_check.organization_id=gathering.organization_id
              AND group_check.status='active'
          )
      )
    ) THEN
      RAISE EXCEPTION 'Organization event attendees must be active Circle members';
    END IF;

    DELETE FROM public.circle_gathering_attendance_records
    WHERE gathering_id=gathering.id;

    INSERT INTO public.circle_gathering_attendance_records(
      organization_id,gathering_id,person_id,recorded_by
    )
      SELECT gathering.organization_id,gathering.id,attendee_person_id,auth.uid()
      FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id;

    INSERT INTO public.circle_gathering_attendance_records(
      organization_id,gathering_id,guest_rsvp_id,recorded_by
    )
      SELECT gathering.organization_id,gathering.id,rsvp_id,auth.uid()
      FROM unnest(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[])) rsvp_id
      WHERE EXISTS(
        SELECT 1 FROM public.circle_guest_rsvps rsvp
        WHERE rsvp.id=rsvp_id AND rsvp.gathering_id=gathering.id
      );

    UPDATE public.circle_guest_rsvps
    SET attended_at=CASE
      WHEN id=ANY(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[]))
        THEN COALESCE(attended_at,now())
      ELSE NULL
    END,
    updated_at=now()
    WHERE gathering_id=gathering.id;

    UPDATE public.circle_gatherings
    SET attendance_saved_at=now(),updated_at=now()
    WHERE id=gathering.id;
    SELECT id INTO record_id
    FROM public.circle_gathering_attendance_records
    WHERE gathering_id=gathering.id
    ORDER BY created_at LIMIT 1;
    RETURN COALESCE(record_id,gathering.id);
  END IF;

  IF EXISTS(
    SELECT 1 FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id
    WHERE NOT EXISTS(
      SELECT 1 FROM public.people person
      WHERE person.id=attendee_person_id
        AND person.organization_id=gathering.organization_id
    )
  ) THEN
    RAISE EXCEPTION 'An attendee is outside this organization';
  END IF;

  SELECT * INTO group_row FROM public.cell_groups WHERE id=gathering.cell_group_id;
  SELECT concat_ws(' ',person.first_name,person.last_name)
  INTO leader_name
  FROM public.people person
  WHERE person.id=COALESCE(gathering.leader_person_id,group_row.leader_person_id);
  leader_name:=COALESCE(nullif(leader_name,''),'Circle leader');

  INSERT INTO public.cell_group_sessions(
    organization_id,cell_group_id,session_date,leader_person_id,leader_name,location
  ) VALUES(
    gathering.organization_id,gathering.cell_group_id,
    (gathering.starts_at AT TIME ZONE 'UTC')::date,
    COALESCE(gathering.leader_person_id,group_row.leader_person_id),
    leader_name,gathering.location
  )
  ON CONFLICT(cell_group_id,session_date) DO UPDATE SET
    leader_person_id=excluded.leader_person_id,
    leader_name=excluded.leader_name,
    location=excluded.location,
    updated_at=now()
  RETURNING id INTO v_session_id;

  DELETE FROM public.cell_group_session_attendees attendee
  WHERE attendee.session_id=v_session_id;
  INSERT INTO public.cell_group_session_attendees(session_id,person_id)
    SELECT v_session_id,attendee_person_id
    FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) attendee_person_id
    ON CONFLICT(session_id,person_id) DO NOTHING;

  UPDATE public.circle_guest_rsvps
  SET attended_at=CASE
    WHEN id=ANY(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[]))
      THEN COALESCE(attended_at,now())
    ELSE NULL
  END,
  updated_at=now()
  WHERE gathering_id=gathering.id;

  UPDATE public.circle_gatherings
  SET attendance_session_id=v_session_id,attendance_saved_at=now(),updated_at=now()
  WHERE id=gathering.id;
  RETURN v_session_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.get_circle_gathering_attendance(
  p_gathering_id UUID
)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  gathering public.circle_gatherings%ROWTYPE;
  result JSONB;
BEGIN
  SELECT * INTO gathering FROM public.circle_gatherings WHERE id=p_gathering_id;
  IF gathering.id IS NULL OR NOT public.circle_can_manage_gathering(gathering.id) THEN
    RAISE EXCEPTION 'Gathering manager access required';
  END IF;

  SELECT jsonb_build_object(
    'saved',gathering.attendance_saved_at IS NOT NULL,
    'personIds',COALESCE(
      CASE WHEN gathering.scope='organization' THEN (
        SELECT jsonb_agg(record.person_id)
        FROM public.circle_gathering_attendance_records record
        WHERE record.gathering_id=gathering.id AND record.person_id IS NOT NULL
      ) ELSE (
        SELECT jsonb_agg(attendee.person_id)
        FROM public.cell_group_session_attendees attendee
        WHERE attendee.session_id=gathering.attendance_session_id
      ) END,
      '[]'::jsonb
    ),
    'guestRsvpIds',COALESCE((
      SELECT jsonb_agg(rsvp.id)
      FROM public.circle_guest_rsvps rsvp
      WHERE rsvp.gathering_id=gathering.id AND rsvp.attended_at IS NOT NULL
    ),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;
CREATE OR REPLACE FUNCTION public.set_circle_gathering_completion(
  p_gathering_id UUID,
  p_completed BOOLEAN
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE gathering public.circle_gatherings%ROWTYPE;
BEGIN
  SELECT * INTO gathering FROM public.circle_gatherings WHERE id=p_gathering_id;
  IF gathering.id IS NULL OR NOT public.circle_can_manage_gathering(gathering.id) THEN
    RAISE EXCEPTION 'Gathering manager access required';
  END IF;
  IF gathering.status='cancelled' THEN
    RAISE EXCEPTION 'A cancelled gathering cannot be completed or reopened';
  END IF;
  IF p_completed AND gathering.starts_at>now() THEN
    RAISE EXCEPTION 'A gathering cannot be completed before it begins';
  END IF;
  UPDATE public.circle_gatherings
  SET status=CASE WHEN p_completed THEN 'completed' ELSE 'scheduled' END,
      updated_at=now()
  WHERE id=gathering.id;
END;
$$;
REVOKE ALL ON FUNCTION public.set_circle_gathering_completion(UUID,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_circle_gathering_completion(UUID,BOOLEAN) TO authenticated;
REVOKE ALL ON FUNCTION public.get_circle_gathering_attendance(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_circle_gathering_attendance(UUID) TO authenticated;
-- Restore future gatherings that the previous attendance-save side effect hid.
UPDATE public.circle_gatherings
SET status='scheduled',updated_at=now()
WHERE status='completed' AND starts_at>now();
COMMIT;
