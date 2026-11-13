CREATE OR REPLACE FUNCTION public.record_circle_audit_event()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  row_data JSONB:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  old_data JSONB:=CASE WHEN TG_OP='UPDATE' THEN to_jsonb(OLD) ELSE '{}'::jsonb END;
  organization_id UUID;
  target_id TEXT;
  changed_fields JSONB:='[]'::jsonb;
BEGIN
  organization_id:=NULLIF(row_data->>'organization_id','')::UUID;
  IF organization_id IS NULL AND row_data ? 'cell_group_id' THEN
    SELECT group_row.organization_id INTO organization_id
    FROM public.cell_groups group_row
    WHERE group_row.id=NULLIF(row_data->>'cell_group_id','')::UUID;
  END IF;
  target_id:=COALESCE(row_data->>'id',row_data->>'person_id',row_data->>'user_id');
  IF TG_OP='UPDATE' THEN
    SELECT COALESCE(jsonb_agg(field ORDER BY field),'[]'::jsonb) INTO changed_fields
    FROM jsonb_object_keys(row_data) AS fields(field)
    WHERE row_data->field IS DISTINCT FROM old_data->field
      AND field NOT IN ('updated_at','password','token','secret');
  END IF;
  INSERT INTO public.circle_security_audit_events(
    organization_id,actor_user_id,action,target_type,target_id,result,request_id,metadata
  ) VALUES(
    organization_id,auth.uid(),TG_ARGV[0]||'.'||lower(TG_OP),TG_TABLE_NAME,target_id,
    'success','database-'||gen_random_uuid()::text,
    CASE WHEN TG_OP='UPDATE' THEN jsonb_build_object('changedFields',changed_fields) ELSE '{}'::jsonb END
  );
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER audit_circle_memberships
AFTER INSERT OR UPDATE OR DELETE ON public.cell_group_members
FOR EACH ROW EXECUTE FUNCTION public.record_circle_audit_event('membership');
CREATE TRIGGER audit_circle_user_links
AFTER INSERT OR UPDATE OR DELETE ON public.circle_user_links
FOR EACH ROW EXECUTE FUNCTION public.record_circle_audit_event('account_access');
CREATE TRIGGER audit_circle_leadership
AFTER INSERT OR UPDATE OR DELETE ON public.cell_groups
FOR EACH ROW EXECUTE FUNCTION public.record_circle_audit_event('leadership');
CREATE TRIGGER audit_circle_publishing
AFTER INSERT OR UPDATE OR DELETE ON public.circle_testimonies
FOR EACH ROW EXECUTE FUNCTION public.record_circle_audit_event('publishing');
CREATE TRIGGER audit_circle_gatherings
AFTER INSERT OR UPDATE OR DELETE ON public.circle_gatherings
FOR EACH ROW EXECUTE FUNCTION public.record_circle_audit_event('gathering');
CREATE TRIGGER audit_circle_attendance
AFTER INSERT OR UPDATE OR DELETE ON public.circle_gathering_attendance_records
FOR EACH ROW EXECUTE FUNCTION public.record_circle_audit_event('attendance');
CREATE TRIGGER audit_circle_guest_consent
AFTER INSERT OR UPDATE OR DELETE ON public.circle_guest_connections
FOR EACH ROW EXECUTE FUNCTION public.record_circle_audit_event('guest_consent');
CREATE TRIGGER audit_circle_signups
AFTER INSERT OR UPDATE OR DELETE ON public.circle_group_signups
FOR EACH ROW EXECUTE FUNCTION public.record_circle_audit_event('signup');
CREATE TRIGGER audit_circle_prayers
AFTER INSERT OR UPDATE OR DELETE ON public.circle_prayer_requests
FOR EACH ROW EXECUTE FUNCTION public.record_circle_audit_event('prayer');

REVOKE ALL ON FUNCTION public.record_circle_audit_event() FROM PUBLIC,anon,authenticated;
