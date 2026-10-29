-- Memorial records for deceased people (free-text name, optional link to an
-- existing person), plus a "Deceased" person status.

ALTER TABLE public.people DROP CONSTRAINT IF EXISTS people_status_check;
ALTER TABLE public.people
  ADD CONSTRAINT people_status_check
  CHECK (status IN ('Active', 'Inactive', 'Exited', 'Deceased'));
CREATE TABLE public.memorial_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  deceased_name TEXT NOT NULL,
  death_date DATE NOT NULL,
  service_date DATE,
  location TEXT NOT NULL DEFAULT '',
  officiant_name TEXT NOT NULL DEFAULT '',
  survived_by TEXT NOT NULL DEFAULT '',
  photo_url TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX memorial_records_organization_id_idx ON public.memorial_records(organization_id);
CREATE INDEX memorial_records_death_date_idx ON public.memorial_records(death_date DESC);
CREATE INDEX memorial_records_person_id_idx ON public.memorial_records(person_id);
ALTER TABLE public.memorial_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members with memorials module can view memorial records"
  ON public.memorial_records FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = memorial_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(memorial_records.organization_id, 'memorials')
  );
CREATE POLICY "Org members with memorials module can insert memorial records"
  ON public.memorial_records FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = memorial_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(memorial_records.organization_id, 'memorials')
  );
CREATE POLICY "Org members with memorials module can update memorial records"
  ON public.memorial_records FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = memorial_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(memorial_records.organization_id, 'memorials')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = memorial_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(memorial_records.organization_id, 'memorials')
  );
CREATE POLICY "Org admins with memorials module can delete memorial records"
  ON public.memorial_records FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = memorial_records.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(memorial_records.organization_id, 'memorials')
  );
-- Photo storage bucket

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'memorial-photos',
  'memorial-photos',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
DROP POLICY IF EXISTS "Memorial photos are publicly accessible" ON storage.objects;
CREATE POLICY "Memorial photos are publicly accessible"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'memorial-photos');
DROP POLICY IF EXISTS "Org members can upload memorial photos" ON storage.objects;
CREATE POLICY "Org members can upload memorial photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'memorial-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'memorials')
  );
DROP POLICY IF EXISTS "Org members can update memorial photos" ON storage.objects;
CREATE POLICY "Org members can update memorial photos"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'memorial-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'memorials')
  )
  WITH CHECK (
    bucket_id = 'memorial-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'memorials')
  );
DROP POLICY IF EXISTS "Org admins can delete memorial photos" ON storage.objects;
CREATE POLICY "Org admins can delete memorial photos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'memorial-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'memorials')
  );
