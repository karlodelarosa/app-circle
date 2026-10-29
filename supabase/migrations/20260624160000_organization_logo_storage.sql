-- Organization logo storage bucket

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'organization-logos',
  'organization-logos',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
DROP POLICY IF EXISTS "Organization logos are publicly accessible" ON storage.objects;
CREATE POLICY "Organization logos are publicly accessible"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'organization-logos');
DROP POLICY IF EXISTS "Org admins can upload organization logos" ON storage.objects;
CREATE POLICY "Org admins can upload organization logos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'organization-logos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org admins can update organization logos" ON storage.objects;
CREATE POLICY "Org admins can update organization logos"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'organization-logos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    bucket_id = 'organization-logos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
DROP POLICY IF EXISTS "Org admins can delete organization logos" ON storage.objects;
CREATE POLICY "Org admins can delete organization logos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'organization-logos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.role = 'admin'
        AND om.status = 'active'
    )
  );
