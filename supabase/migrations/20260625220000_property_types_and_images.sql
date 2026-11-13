-- Configurable property types, optional images, remove address

CREATE TABLE IF NOT EXISTS public.property_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name)
);
CREATE INDEX IF NOT EXISTS property_types_organization_id_idx
  ON public.property_types(organization_id);
ALTER TABLE public.property_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members with properties module can view property types"
  ON public.property_types FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = property_types.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(property_types.organization_id, 'properties')
  );
CREATE POLICY "Org admins with properties module can insert property types"
  ON public.property_types FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = property_types.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(property_types.organization_id, 'properties')
  );
CREATE POLICY "Org admins with properties module can update property types"
  ON public.property_types FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = property_types.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(property_types.organization_id, 'properties')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = property_types.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(property_types.organization_id, 'properties')
  );
-- Seed default property types for all organizations
INSERT INTO public.property_types (organization_id, name, sort_order)
SELECT o.id, defaults.name, defaults.sort_order
FROM public.organizations o
CROSS JOIN (
  VALUES
    ('Building', 1),
    ('Land', 2),
    ('Vehicle', 3),
    ('Equipment', 4)
) AS defaults(name, sort_order)
ON CONFLICT (organization_id, name) DO NOTHING;
-- church_properties schema updates
ALTER TABLE public.church_properties
  ADD COLUMN IF NOT EXISTS property_type_id UUID REFERENCES public.property_types(id),
  ADD COLUMN IF NOT EXISTS image_url TEXT NOT NULL DEFAULT '';
-- Migrate legacy type text column to property_type_id when present
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'church_properties'
      AND column_name = 'type'
  ) THEN
    UPDATE public.church_properties cp
    SET property_type_id = pt.id
    FROM public.property_types pt
    WHERE cp.property_type_id IS NULL
      AND pt.organization_id = cp.organization_id
      AND pt.name = cp.type;

    UPDATE public.church_properties cp
    SET property_type_id = pt.id
    FROM public.property_types pt
    WHERE cp.property_type_id IS NULL
      AND pt.organization_id = cp.organization_id
      AND pt.name = 'Equipment';

    ALTER TABLE public.church_properties DROP COLUMN type;
  END IF;
END $$;
-- Backfill any rows still missing a type
UPDATE public.church_properties cp
SET property_type_id = pt.id
FROM public.property_types pt
WHERE cp.property_type_id IS NULL
  AND pt.organization_id = cp.organization_id
  AND pt.name = 'Equipment';
ALTER TABLE public.church_properties
  ALTER COLUMN property_type_id SET NOT NULL;
ALTER TABLE public.church_properties
  DROP COLUMN IF EXISTS address;
-- Property image storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'property-images',
  'property-images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
DROP POLICY IF EXISTS "Property images are publicly accessible" ON storage.objects;
CREATE POLICY "Property images are publicly accessible"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'property-images');
DROP POLICY IF EXISTS "Org members can upload property images" ON storage.objects;
CREATE POLICY "Org members can upload property images"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'property-images'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'properties')
  );
DROP POLICY IF EXISTS "Org members can update property images" ON storage.objects;
CREATE POLICY "Org members can update property images"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'property-images'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'properties')
  )
  WITH CHECK (
    bucket_id = 'property-images'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'properties')
  );
DROP POLICY IF EXISTS "Org admins can delete property images" ON storage.objects;
CREATE POLICY "Org admins can delete property images"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'property-images'
    AND EXISTS (
      SELECT 1
      FROM public.organization_members om
      WHERE om.user_id = auth.uid()
        AND om.organization_id = (storage.foldername(name))[1]::uuid
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module((storage.foldername(name))[1]::uuid, 'properties')
  );
