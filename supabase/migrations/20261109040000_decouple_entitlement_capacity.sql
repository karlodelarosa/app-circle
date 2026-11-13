-- Keep subscription-capacity enforcement independent from caller authorization.
-- Operation-specific RPCs and table RLS remain responsible for access control.

CREATE OR REPLACE FUNCTION public.org_people_capacity_available(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.get_org_people_count(p_org_id) < limits.max_people
  FROM public.get_org_subscription_row(p_org_id) limits;
$$;

CREATE OR REPLACE FUNCTION public.org_attendance_capacity_available(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.get_org_attendance_session_count(p_org_id) < limits.max_attendance_sessions
  FROM public.get_org_subscription_row(p_org_id) limits;
$$;

REVOKE ALL ON FUNCTION public.org_people_capacity_available(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.org_attendance_capacity_available(UUID)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.org_can_add_person(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.caller_can_access_org(p_org_id)
    AND coalesce(public.org_people_capacity_available(p_org_id), false);
$$;

CREATE OR REPLACE FUNCTION public.org_can_add_attendance_session(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.caller_can_access_org(p_org_id)
    AND coalesce(public.org_attendance_capacity_available(p_org_id), false);
$$;

CREATE OR REPLACE FUNCTION public.enforce_people_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  capacity_available BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    capacity_available := public.org_people_capacity_available(NEW.organization_id);
    IF capacity_available IS NULL THEN
      RAISE EXCEPTION 'Organization subscription is not configured';
    ELSIF NOT capacity_available THEN
      RAISE EXCEPTION 'People limit reached for this organization';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_attendance_session_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  capacity_available BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    capacity_available := public.org_attendance_capacity_available(NEW.organization_id);
    IF capacity_available IS NULL THEN
      RAISE EXCEPTION 'Organization subscription is not configured';
    ELSIF NOT capacity_available THEN
      RAISE EXCEPTION 'Attendance session limit reached for this organization';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
