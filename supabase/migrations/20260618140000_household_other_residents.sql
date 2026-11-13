-- Non-attending people who live at a household (tenants, relatives, etc.)
CREATE TABLE public.household_other_residents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL DEFAULT '',
  relation TEXT NOT NULL DEFAULT 'Other'
    CHECK (relation IN ('Tenant', 'Friend', 'Relative', 'Other')),
  phone TEXT NOT NULL DEFAULT '',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX household_other_residents_household_id_idx
  ON public.household_other_residents(household_id);
CREATE INDEX household_other_residents_organization_id_idx
  ON public.household_other_residents(organization_id);
ALTER TABLE public.household_other_residents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members can view household other residents"
  ON public.household_other_residents FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = household_other_residents.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert household other residents"
  ON public.household_other_residents FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = household_other_residents.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update household other residents"
  ON public.household_other_residents FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = household_other_residents.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = household_other_residents.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete household other residents"
  ON public.household_other_residents FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = household_other_residents.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
