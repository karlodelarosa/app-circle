-- Church properties and borrow log (properties module)

CREATE TABLE public.church_properties (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL DEFAULT 'Equipment' CHECK (
    type IN ('Building', 'Land', 'Vehicle', 'Equipment')
  ),
  address TEXT NOT NULL DEFAULT '',
  purchase_date DATE,
  estimated_value NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (estimated_value >= 0),
  status TEXT NOT NULL DEFAULT 'owned' CHECK (
    status IN ('owned', 'borrowed', 'lost')
  ),
  notes TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.property_borrows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id UUID NOT NULL REFERENCES public.church_properties(id) ON DELETE CASCADE,
  borrower_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  borrower_name TEXT NOT NULL DEFAULT '',
  borrowed_at DATE NOT NULL,
  due_at DATE,
  returned_at DATE,
  notes TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX church_properties_organization_id_idx
  ON public.church_properties(organization_id);
CREATE INDEX church_properties_status_idx
  ON public.church_properties(status);
CREATE INDEX church_properties_type_idx
  ON public.church_properties(type);
CREATE INDEX property_borrows_property_id_idx
  ON public.property_borrows(property_id);
CREATE INDEX property_borrows_borrower_person_id_idx
  ON public.property_borrows(borrower_person_id);
CREATE INDEX property_borrows_borrowed_at_idx
  ON public.property_borrows(borrowed_at DESC);
CREATE INDEX property_borrows_returned_at_idx
  ON public.property_borrows(returned_at);
ALTER TABLE public.church_properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.property_borrows ENABLE ROW LEVEL SECURITY;
-- church_properties policies
CREATE POLICY "Org members with properties module can view church properties"
  ON public.church_properties FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_properties.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(church_properties.organization_id, 'properties')
  );
CREATE POLICY "Org admins with properties module can insert church properties"
  ON public.church_properties FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_properties.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_properties.organization_id, 'properties')
  );
CREATE POLICY "Org admins with properties module can update church properties"
  ON public.church_properties FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_properties.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_properties.organization_id, 'properties')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_properties.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_properties.organization_id, 'properties')
  );
CREATE POLICY "Org admins with properties module can delete church properties"
  ON public.church_properties FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = church_properties.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(church_properties.organization_id, 'properties')
  );
-- property_borrows policies
CREATE POLICY "Org members with properties module can view property borrows"
  ON public.property_borrows FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_properties cp
      JOIN public.organization_members om ON om.organization_id = cp.organization_id
      WHERE cp.id = property_borrows.property_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_properties cp
      WHERE cp.id = property_borrows.property_id
        AND public.org_has_module(cp.organization_id, 'properties')
    )
  );
CREATE POLICY "Org members with properties module can insert property borrows"
  ON public.property_borrows FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_properties cp
      JOIN public.organization_members om ON om.organization_id = cp.organization_id
      WHERE cp.id = property_borrows.property_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_properties cp
      WHERE cp.id = property_borrows.property_id
        AND public.org_has_module(cp.organization_id, 'properties')
    )
  );
CREATE POLICY "Org members with properties module can update property borrows"
  ON public.property_borrows FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_properties cp
      JOIN public.organization_members om ON om.organization_id = cp.organization_id
      WHERE cp.id = property_borrows.property_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_properties cp
      WHERE cp.id = property_borrows.property_id
        AND public.org_has_module(cp.organization_id, 'properties')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.church_properties cp
      JOIN public.organization_members om ON om.organization_id = cp.organization_id
      WHERE cp.id = property_borrows.property_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_properties cp
      WHERE cp.id = property_borrows.property_id
        AND public.org_has_module(cp.organization_id, 'properties')
    )
  );
CREATE POLICY "Org admins with properties module can delete property borrows"
  ON public.property_borrows FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.church_properties cp
      JOIN public.organization_members om ON om.organization_id = cp.organization_id
      WHERE cp.id = property_borrows.property_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.church_properties cp
      WHERE cp.id = property_borrows.property_id
        AND public.org_has_module(cp.organization_id, 'properties')
    )
  );
