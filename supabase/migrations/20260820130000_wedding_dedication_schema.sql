-- Wedding and child dedication records (free-text participants, not tied to `people`)

CREATE TABLE IF NOT EXISTS public.wedding_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  spouse1_name TEXT NOT NULL,
  spouse2_name TEXT NOT NULL,
  married_at DATE NOT NULL,
  location TEXT NOT NULL DEFAULT '',
  officiant_name TEXT NOT NULL DEFAULT '',
  witnesses TEXT NOT NULL DEFAULT '',
  license_number TEXT NOT NULL DEFAULT '',
  license_authority TEXT NOT NULL DEFAULT '',
  photo_url TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS wedding_records_organization_id_idx ON public.wedding_records(organization_id);
CREATE INDEX IF NOT EXISTS wedding_records_married_at_idx ON public.wedding_records(married_at DESC);
CREATE TABLE IF NOT EXISTS public.dedication_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  child_name TEXT NOT NULL,
  parent_names TEXT NOT NULL DEFAULT '',
  dedicated_at DATE NOT NULL,
  location TEXT NOT NULL DEFAULT '',
  officiant_name TEXT NOT NULL DEFAULT '',
  sponsors TEXT NOT NULL DEFAULT '',
  photo_url TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS dedication_records_organization_id_idx ON public.dedication_records(organization_id);
CREATE INDEX IF NOT EXISTS dedication_records_dedicated_at_idx ON public.dedication_records(dedicated_at DESC);
ALTER TABLE public.wedding_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dedication_records ENABLE ROW LEVEL SECURITY;
-- wedding_records policies

DROP POLICY IF EXISTS "Org members with weddings module can view wedding records" ON public.wedding_records;
CREATE POLICY "Org members with weddings module can view wedding records"
  ON public.wedding_records FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = wedding_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(wedding_records.organization_id, 'weddings')
  );
DROP POLICY IF EXISTS "Org members with weddings module can insert wedding records" ON public.wedding_records;
CREATE POLICY "Org members with weddings module can insert wedding records"
  ON public.wedding_records FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = wedding_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(wedding_records.organization_id, 'weddings')
  );
DROP POLICY IF EXISTS "Org members with weddings module can update wedding records" ON public.wedding_records;
CREATE POLICY "Org members with weddings module can update wedding records"
  ON public.wedding_records FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = wedding_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(wedding_records.organization_id, 'weddings')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = wedding_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(wedding_records.organization_id, 'weddings')
  );
DROP POLICY IF EXISTS "Org admins with weddings module can delete wedding records" ON public.wedding_records;
CREATE POLICY "Org admins with weddings module can delete wedding records"
  ON public.wedding_records FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = wedding_records.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(wedding_records.organization_id, 'weddings')
  );
-- dedication_records policies

DROP POLICY IF EXISTS "Org members with dedications module can view dedication records" ON public.dedication_records;
CREATE POLICY "Org members with dedications module can view dedication records"
  ON public.dedication_records FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = dedication_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(dedication_records.organization_id, 'dedications')
  );
DROP POLICY IF EXISTS "Org members with dedications module can insert dedication records" ON public.dedication_records;
CREATE POLICY "Org members with dedications module can insert dedication records"
  ON public.dedication_records FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = dedication_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(dedication_records.organization_id, 'dedications')
  );
DROP POLICY IF EXISTS "Org members with dedications module can update dedication records" ON public.dedication_records;
CREATE POLICY "Org members with dedications module can update dedication records"
  ON public.dedication_records FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = dedication_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(dedication_records.organization_id, 'dedications')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = dedication_records.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(dedication_records.organization_id, 'dedications')
  );
DROP POLICY IF EXISTS "Org admins with dedications module can delete dedication records" ON public.dedication_records;
CREATE POLICY "Org admins with dedications module can delete dedication records"
  ON public.dedication_records FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = dedication_records.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(dedication_records.organization_id, 'dedications')
  );
-- Photo storage buckets

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'wedding-photos',
  'wedding-photos',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'dedication-photos',
  'dedication-photos',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
DROP POLICY IF EXISTS "Wedding photos are publicly accessible" ON storage.objects;
CREATE POLICY "Wedding photos are publicly accessible"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'wedding-photos');
DROP POLICY IF EXISTS "Org members can upload wedding photos" ON storage.objects;
CREATE POLICY "Org members can upload wedding photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'wedding-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'weddings')
  );
DROP POLICY IF EXISTS "Org members can update wedding photos" ON storage.objects;
CREATE POLICY "Org members can update wedding photos"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'wedding-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'weddings')
  )
  WITH CHECK (
    bucket_id = 'wedding-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'weddings')
  );
DROP POLICY IF EXISTS "Org admins can delete wedding photos" ON storage.objects;
CREATE POLICY "Org admins can delete wedding photos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'wedding-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'weddings')
  );
DROP POLICY IF EXISTS "Dedication photos are publicly accessible" ON storage.objects;
CREATE POLICY "Dedication photos are publicly accessible"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'dedication-photos');
DROP POLICY IF EXISTS "Org members can upload dedication photos" ON storage.objects;
CREATE POLICY "Org members can upload dedication photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'dedication-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'dedications')
  );
DROP POLICY IF EXISTS "Org members can update dedication photos" ON storage.objects;
CREATE POLICY "Org members can update dedication photos"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'dedication-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'dedications')
  )
  WITH CHECK (
    bucket_id = 'dedication-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'dedications')
  );
DROP POLICY IF EXISTS "Org admins can delete dedication photos" ON storage.objects;
CREATE POLICY "Org admins can delete dedication photos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'dedication-photos'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'dedications')
  );
