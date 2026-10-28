-- Historical attendance can include visitors whose name is the only known detail.
-- Keep these gathering-specific unless contact details justify a Connection record.

BEGIN;

ALTER TABLE public.circle_guest_rsvps
  ADD COLUMN IF NOT EXISTS entry_source TEXT NOT NULL DEFAULT 'rsvp';

UPDATE public.circle_guest_rsvps
SET entry_source='rsvp'
WHERE entry_source IS NULL;

ALTER TABLE public.circle_guest_rsvps
  ALTER COLUMN entry_source SET DEFAULT 'rsvp',
  ALTER COLUMN entry_source SET NOT NULL,
  DROP CONSTRAINT IF EXISTS circle_guest_rsvps_entry_source_check,
  ADD CONSTRAINT circle_guest_rsvps_entry_source_check
    CHECK (entry_source IN ('rsvp','walk_in'));

CREATE OR REPLACE FUNCTION public.stage_circle_walk_in(
  p_gathering_id UUID,
  p_name TEXT,
  p_email TEXT,
  p_phone TEXT,
  p_preferred_contact TEXT,
  p_consent BOOLEAN
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  gathering public.circle_gatherings%ROWTYPE;
  connection_id UUID;
  rsvp_id UUID:=gen_random_uuid();
  contact_key TEXT;
  email_value TEXT:=lower(trim(COALESCE(p_email,'')));
  phone_value TEXT:=trim(COALESCE(p_phone,''));
  has_contact BOOLEAN;
BEGIN
  SELECT * INTO gathering
  FROM public.circle_gatherings
  WHERE id=p_gathering_id;

  IF gathering.id IS NULL OR NOT public.circle_can_manage_gathering(gathering.id) THEN
    RAISE EXCEPTION 'Gathering manager access required';
  END IF;
  IF gathering.status<>'scheduled' OR gathering.starts_at>now() THEN
    RAISE EXCEPTION 'Attendance is unavailable before the gathering begins or after it is completed';
  END IF;
  IF nullif(trim(p_name),'') IS NULL OR char_length(trim(p_name))>120 THEN
    RAISE EXCEPTION 'Guest name must be between 1 and 120 characters';
  END IF;

  has_contact:=email_value<>'' OR phone_value<>'';
  IF has_contact AND gathering.cell_group_id IS NULL THEN
    RAISE EXCEPTION 'Contact details can only be added to a Circle gathering';
  END IF;

  IF has_contact THEN
    contact_key:=public.circle_normalize_guest_contact(email_value,phone_value,'');
    connection_id:=public.circle_upsert_guest_connection(
      gathering.organization_id,
      gathering.cell_group_id,
      trim(p_name),
      email_value,
      phone_value,
      '',
      p_preferred_contact,
      p_consent,
      CASE WHEN p_consent THEN now() ELSE NULL END
    );

    INSERT INTO public.circle_guest_rsvps(
      id,organization_id,gathering_id,guest_name,email,phone,
      normalized_contact,status,connection_id,entry_source
    ) VALUES(
      rsvp_id,gathering.organization_id,gathering.id,trim(p_name),email_value,phone_value,
      contact_key,'attending',connection_id,'walk_in'
    )
    ON CONFLICT(gathering_id,normalized_contact) DO UPDATE SET
      guest_name=excluded.guest_name,
      email=excluded.email,
      phone=excluded.phone,
      status='attending',
      connection_id=excluded.connection_id,
      updated_at=now()
    RETURNING id INTO rsvp_id;
  ELSE
    contact_key:='attendance:'||rsvp_id::TEXT;
    INSERT INTO public.circle_guest_rsvps(
      id,organization_id,gathering_id,guest_name,email,phone,
      normalized_contact,status,connection_id,entry_source
    ) VALUES(
      rsvp_id,gathering.organization_id,gathering.id,trim(p_name),'','',
      contact_key,'attending',NULL,'walk_in'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok',true,
    'guestRsvpId',rsvp_id,
    'connectionId',connection_id
  );
END;
$$;

-- A staged visitor becomes a visit only when attendance is explicitly saved.
CREATE OR REPLACE FUNCTION public.circle_mark_saved_guest_visit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.connection_id IS NOT NULL
     AND NEW.attended_at IS NOT NULL
     AND OLD.attended_at IS NULL THEN
    UPDATE public.circle_guest_connections
    SET status=CASE WHEN status IN ('new','contacted') THEN 'visited' ELSE status END,
        last_activity_at=now(),
        updated_at=now()
    WHERE id=NEW.connection_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS circle_guest_rsvp_saved_visit
  ON public.circle_guest_rsvps;
CREATE TRIGGER circle_guest_rsvp_saved_visit
AFTER UPDATE OF attended_at ON public.circle_guest_rsvps
FOR EACH ROW
EXECUTE FUNCTION public.circle_mark_saved_guest_visit();

REVOKE ALL ON FUNCTION public.stage_circle_walk_in(UUID,TEXT,TEXT,TEXT,TEXT,BOOLEAN)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.stage_circle_walk_in(UUID,TEXT,TEXT,TEXT,TEXT,BOOLEAN)
  TO authenticated;

COMMIT;
