-- Subscription cancellation reason and secure cancel RPC

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS cancellation_reason TEXT,
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE OR REPLACE FUNCTION public.cancel_organization_subscription(
  p_organization_id UUID,
  p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.is_org_admin(p_organization_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF trim(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'Cancellation reason is required';
  END IF;

  UPDATE public.subscriptions
  SET
    cancel_at_period_end = true,
    cancellation_reason = trim(p_reason),
    cancelled_at = now(),
    cancelled_by_user_id = auth.uid(),
    updated_at = now()
  WHERE organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Subscription not found';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_organization_subscription(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_organization_subscription(UUID, TEXT) TO authenticated;
