-- Add Youth Fellowship to default service types and backfill existing organizations

CREATE OR REPLACE FUNCTION public.seed_default_service_types(org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.service_types WHERE organization_id = org_id) THEN
    INSERT INTO public.service_types (organization_id, name, category, sort_order)
    VALUES
      (org_id, 'Sunday Service', 'sunday', 1),
      (org_id, 'Sunday School', 'life_group', 2),
      (org_id, 'Men''s Fellowship', 'life_group', 3),
      (org_id, 'Ladies'' Fellowship', 'life_group', 4),
      (org_id, 'Young Professionals Fellowship', 'life_group', 5),
      (org_id, 'Prayer Meeting', 'life_group', 6),
      (org_id, 'Youth Fellowship', 'life_group', 7);
  END IF;
END;
$$;
INSERT INTO public.service_types (organization_id, name, category, sort_order)
SELECT o.id, 'Youth Fellowship', 'life_group', 7
FROM public.organizations o
WHERE NOT EXISTS (
  SELECT 1
  FROM public.service_types st
  WHERE st.organization_id = o.id
    AND st.name = 'Youth Fellowship'
);
