BEGIN;

REVOKE ALL ON FUNCTION public.get_my_circle_account_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_circle_member_account_statuses(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.deactivate_circle_access_after_membership_delete() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_my_circle_account_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_circle_member_account_statuses(UUID) TO authenticated;

COMMIT;
