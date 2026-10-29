-- Configurable receipt types and expense categories per organization

CREATE TABLE IF NOT EXISTS public.financial_receipt_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name)
);
CREATE TABLE IF NOT EXISTS public.financial_expense_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name)
);
CREATE INDEX IF NOT EXISTS financial_receipt_types_organization_id_idx
  ON public.financial_receipt_types(organization_id);
CREATE INDEX IF NOT EXISTS financial_expense_categories_organization_id_idx
  ON public.financial_expense_categories(organization_id);
ALTER TABLE public.financial_receipt_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_audit_income_entries
  DROP CONSTRAINT IF EXISTS financial_audit_income_entries_type_check;
-- financial_receipt_types policies
DROP POLICY IF EXISTS "Org members with financial module can view receipt types"
  ON public.financial_receipt_types;
CREATE POLICY "Org members with financial module can view receipt types"
  ON public.financial_receipt_types FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_receipt_types.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_receipt_types.organization_id, 'financial')
  );
DROP POLICY IF EXISTS "Org members with financial module can insert receipt types"
  ON public.financial_receipt_types;
CREATE POLICY "Org members with financial module can insert receipt types"
  ON public.financial_receipt_types FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_receipt_types.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_receipt_types.organization_id, 'financial')
  );
DROP POLICY IF EXISTS "Org members with financial module can update receipt types"
  ON public.financial_receipt_types;
CREATE POLICY "Org members with financial module can update receipt types"
  ON public.financial_receipt_types FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_receipt_types.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_receipt_types.organization_id, 'financial')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_receipt_types.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_receipt_types.organization_id, 'financial')
  );
-- financial_expense_categories policies
DROP POLICY IF EXISTS "Org members with financial module can view expense categories"
  ON public.financial_expense_categories;
CREATE POLICY "Org members with financial module can view expense categories"
  ON public.financial_expense_categories FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_expense_categories.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_expense_categories.organization_id, 'financial')
  );
DROP POLICY IF EXISTS "Org members with financial module can insert expense categories"
  ON public.financial_expense_categories;
CREATE POLICY "Org members with financial module can insert expense categories"
  ON public.financial_expense_categories FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_expense_categories.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_expense_categories.organization_id, 'financial')
  );
DROP POLICY IF EXISTS "Org members with financial module can update expense categories"
  ON public.financial_expense_categories;
CREATE POLICY "Org members with financial module can update expense categories"
  ON public.financial_expense_categories FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_expense_categories.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_expense_categories.organization_id, 'financial')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_expense_categories.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_expense_categories.organization_id, 'financial')
  );
-- Seed defaults for existing organizations
INSERT INTO public.financial_receipt_types (organization_id, name, sort_order)
SELECT o.id, v.name, v.sort_order
FROM public.organizations o
CROSS JOIN (
  VALUES
    ('Tithes', 1),
    ('Offering', 2),
    ('Donation', 3)
) AS v(name, sort_order)
ON CONFLICT (organization_id, name) DO NOTHING;
INSERT INTO public.financial_expense_categories (organization_id, name, sort_order)
SELECT o.id, v.name, v.sort_order
FROM public.organizations o
CROSS JOIN (
  VALUES
    ('Electricity', 1),
    ('Water Meter', 2),
    ('Rent', 3),
    ('Resources (Food, Water)', 4),
    ('Salaries', 5),
    ('Building Maintenance', 6),
    ('Ministry Supplies', 7),
    ('Missions Support', 8),
    ('Insurance', 9),
    ('Technology', 10),
    ('Other', 11)
) AS v(name, sort_order)
ON CONFLICT (organization_id, name) DO NOTHING;
