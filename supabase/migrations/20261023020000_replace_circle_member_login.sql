BEGIN;

ALTER TABLE public.circle_account_transitions
  DROP CONSTRAINT IF EXISTS circle_account_transitions_action_check;
ALTER TABLE public.circle_account_transitions
  ADD CONSTRAINT circle_account_transitions_action_check
  CHECK (action IN (
    'generated_to_sheepcount',
    'leadership_approved',
    'badge_awarded',
    'badge_revoked',
    'login_replaced'
  ));

CREATE OR REPLACE FUNCTION public.replace_circle_member_login(
  p_cell_group_id UUID,
  p_person_id UUID,
  p_new_user_id UUID,
  p_login_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_org UUID;
  v_current public.circle_user_links%ROWTYPE;
BEGIN
  SELECT organization_id INTO v_org
  FROM public.cell_groups
  WHERE id = p_cell_group_id AND status = 'active';

  IF v_org IS NULL OR NOT public.circle_is_org_admin(v_org) THEN
    RAISE EXCEPTION 'Organization administrator access required';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.cell_group_members membership
    JOIN public.people person ON person.id = membership.person_id
    WHERE membership.cell_group_id = p_cell_group_id
      AND membership.person_id = p_person_id
      AND person.organization_id = v_org
      AND person.status = 'Active'
  ) THEN
    RAISE EXCEPTION 'Only active People assigned to this Circle can receive a replacement login';
  END IF;

  SELECT * INTO v_current
  FROM public.circle_user_links
  WHERE organization_id = v_org AND person_id = p_person_id
  FOR UPDATE;

  IF v_current.id IS NULL THEN
    RAISE EXCEPTION 'No existing Circles login was found';
  END IF;
  IF v_current.account_kind <> 'existing' THEN
    RAISE EXCEPTION 'Generated Member IDs should be reset rather than replaced';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.circle_user_links
    WHERE organization_id = v_org AND user_id = p_new_user_id
  ) THEN
    RAISE EXCEPTION 'The replacement login is already in use';
  END IF;

  INSERT INTO public.organization_members(user_id, organization_id, role, status)
  VALUES (p_new_user_id, v_org, 'member', 'active')
  ON CONFLICT (user_id, organization_id) DO UPDATE SET status = 'active';

  UPDATE public.circle_user_links SET
    user_id = p_new_user_id,
    account_kind = 'generated',
    login_id = p_login_id,
    status = 'active',
    must_change_password = true,
    provisioned_by = auth.uid(),
    last_password_reset_at = now(),
    updated_at = now()
  WHERE id = v_current.id;

  INSERT INTO public.circle_account_transitions(
    organization_id, person_id, old_user_id, new_user_id,
    action, note, performed_by
  ) VALUES (
    v_org, p_person_id, v_current.user_id, p_new_user_id,
    'login_replaced',
    'Replaced a SheepCount-linked Circles login with a generated Member ID',
    auth.uid()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.replace_circle_member_login(UUID, UUID, UUID, TEXT)
TO authenticated;

COMMIT;
