BEGIN;

ALTER TABLE public.circle_user_links
  ADD COLUMN IF NOT EXISTS account_kind TEXT NOT NULL DEFAULT 'existing'
    CHECK (account_kind IN ('existing','generated')),
  ADD COLUMN IF NOT EXISTS login_id TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS provisioned_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS last_password_reset_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.get_my_circle_account_state()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT COALESCE((
    SELECT jsonb_build_object(
      'kind', cul.account_kind,
      'loginId', cul.login_id,
      'mustChangePassword', cul.must_change_password,
      'status', cul.status
    )
    FROM public.circle_user_links cul
    WHERE cul.user_id=auth.uid() AND cul.status='active'
    ORDER BY cul.created_at LIMIT 1
  ), '{}'::jsonb);
$$;
GRANT EXECUTE ON FUNCTION public.get_my_circle_account_state() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_circle_member_account_statuses(p_cell_group_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_org UUID;
BEGIN
  SELECT organization_id INTO v_org FROM public.cell_groups WHERE id=p_cell_group_id;
  IF v_org IS NULL OR NOT (public.circle_is_org_admin(v_org) OR public.circle_can_lead_group(p_cell_group_id)) THEN
    RAISE EXCEPTION 'Leader access required';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'personId',m.person_id,'status',COALESCE(cul.status,'none'),
      'kind',cul.account_kind,'loginId',cul.login_id,
      'mustChangePassword',COALESCE(cul.must_change_password,false)
    ) ORDER BY p.last_name,p.first_name)
    FROM public.cell_group_members m
    JOIN public.people p ON p.id=m.person_id
    LEFT JOIN public.circle_user_links cul ON cul.organization_id=p.organization_id AND cul.person_id=p.id
    WHERE m.cell_group_id=p_cell_group_id
  ),'[]'::jsonb);
END; $$;
GRANT EXECUTE ON FUNCTION public.get_circle_member_account_statuses(UUID) TO authenticated;

DROP POLICY IF EXISTS "Circle members submit own testimony drafts" ON public.circle_testimonies;
CREATE POLICY "Circle members submit own testimony drafts" ON public.circle_testimonies
FOR INSERT TO authenticated WITH CHECK(
  status='draft' AND published_at IS NULL AND created_by=auth.uid()
  AND author_person_id=public.circle_current_person_id(organization_id)
  AND cell_group_id IS NOT NULL AND public.circle_can_access_group(cell_group_id)
);
DROP POLICY IF EXISTS "Circle members read own testimony drafts" ON public.circle_testimonies;
CREATE POLICY "Circle members read own testimony drafts" ON public.circle_testimonies
FOR SELECT TO authenticated USING(
  created_by=auth.uid() AND author_person_id=public.circle_current_person_id(organization_id)
);

CREATE OR REPLACE FUNCTION public.deactivate_circle_access_after_membership_delete()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_org UUID;
BEGIN
  SELECT organization_id INTO v_org FROM public.cell_groups WHERE id=OLD.cell_group_id;
  IF NOT EXISTS(
    SELECT 1 FROM public.cell_group_members m
    JOIN public.cell_groups g ON g.id=m.cell_group_id
    WHERE m.person_id=OLD.person_id AND g.organization_id=v_org AND g.status='active'
  ) AND NOT EXISTS(
    SELECT 1 FROM public.cell_groups g
    WHERE g.organization_id=v_org AND g.leader_person_id=OLD.person_id AND g.status='active'
  ) THEN
    UPDATE public.circle_user_links SET status='inactive',updated_at=now()
    WHERE organization_id=v_org AND person_id=OLD.person_id;
  END IF;
  RETURN OLD;
END; $$;
DROP TRIGGER IF EXISTS circle_member_access_offboarding ON public.cell_group_members;
CREATE TRIGGER circle_member_access_offboarding AFTER DELETE ON public.cell_group_members
FOR EACH ROW EXECUTE FUNCTION public.deactivate_circle_access_after_membership_delete();

COMMIT;
