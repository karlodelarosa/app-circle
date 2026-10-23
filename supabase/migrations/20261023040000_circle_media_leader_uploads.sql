BEGIN;

-- Storage policies run against storage.objects. Keep the organization lookup
-- inside the existing SECURITY DEFINER helper so Circle leaders do not need
-- direct visibility into every cell_groups row in their organization.
DROP POLICY IF EXISTS "Leaders upload Circle media" ON storage.objects;
DROP POLICY IF EXISTS "Leaders update Circle media" ON storage.objects;
DROP POLICY IF EXISTS "Leaders delete Circle media" ON storage.objects;

CREATE POLICY "Leaders upload Circle media"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'circle-public-media'
  AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  AND public.circle_can_lead_organization((storage.foldername(name))[1]::uuid)
);

CREATE POLICY "Leaders update Circle media"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'circle-public-media'
  AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  AND public.circle_can_lead_organization((storage.foldername(name))[1]::uuid)
)
WITH CHECK (
  bucket_id = 'circle-public-media'
  AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  AND public.circle_can_lead_organization((storage.foldername(name))[1]::uuid)
);

CREATE POLICY "Leaders delete Circle media"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'circle-public-media'
  AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  AND public.circle_can_lead_organization((storage.foldername(name))[1]::uuid)
);

COMMIT;
