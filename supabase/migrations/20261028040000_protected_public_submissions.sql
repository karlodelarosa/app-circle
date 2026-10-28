-- Anonymous writes must pass through circle-public-submit, which enforces origin,
-- size, schema, bot, and rate-limit checks before invoking these functions as the
-- service role. Rate-limit keys are salted hashes; raw IP addresses are not stored.
CREATE TABLE IF NOT EXISTS public.circle_public_submission_limits (
  key_hash TEXT NOT NULL,
  window_started_at TIMESTAMPTZ NOT NULL,
  request_count INTEGER NOT NULL CHECK (request_count > 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (key_hash, window_started_at)
);

ALTER TABLE public.circle_public_submission_limits ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.circle_consume_public_submission_limit(
  p_key TEXT,
  p_limit INTEGER,
  p_window_seconds INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_window TIMESTAMPTZ;
  v_count INTEGER;
BEGIN
  IF length(p_key) <> 64 OR p_limit NOT BETWEEN 1 AND 100 OR p_window_seconds NOT BETWEEN 60 AND 86400 THEN
    RETURN false;
  END IF;
  v_window := to_timestamp(floor(extract(epoch FROM now()) / p_window_seconds) * p_window_seconds);
  INSERT INTO public.circle_public_submission_limits(key_hash, window_started_at, request_count)
  VALUES (p_key, v_window, 1)
  ON CONFLICT (key_hash, window_started_at) DO UPDATE
    SET request_count=public.circle_public_submission_limits.request_count + 1,
        updated_at=now()
  RETURNING request_count INTO v_count;

  -- Bounded housekeeping keeps this operational table free of long-lived identifiers.
  DELETE FROM public.circle_public_submission_limits
  WHERE window_started_at < now() - interval '2 days';
  RETURN v_count <= p_limit;
END;
$$;

REVOKE ALL ON TABLE public.circle_public_submission_limits FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.circle_consume_public_submission_limit(TEXT,INTEGER,INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.circle_consume_public_submission_limit(TEXT,INTEGER,INTEGER) TO service_role;

REVOKE ALL ON FUNCTION public.submit_circle_guest_rsvp(UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_circle_interest(UUID,TEXT,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.request_circle_connection(UUID,UUID,TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_circle_group_signup(TEXT,TEXT,TEXT,DATE,TEXT,TEXT,BOOLEAN,UUID) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.submit_circle_guest_rsvp(UUID,TEXT,TEXT,TEXT,TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.submit_circle_interest(UUID,TEXT,TEXT,TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.request_circle_connection(UUID,UUID,TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN) TO service_role;
GRANT EXECUTE ON FUNCTION public.submit_circle_group_signup(TEXT,TEXT,TEXT,DATE,TEXT,TEXT,BOOLEAN,UUID) TO service_role;
