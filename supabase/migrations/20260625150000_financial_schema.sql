-- Financial audit schedules and entries (tithes, offerings, donations, expenses)

CREATE TABLE public.financial_audits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  schedule_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.financial_audit_income_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  audit_id UUID NOT NULL REFERENCES public.financial_audits(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('Tithes', 'Offering', 'Donation')),
  source TEXT NOT NULL DEFAULT '',
  amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
  payment_method TEXT NOT NULL DEFAULT 'Cash' CHECK (
    payment_method IN ('Cash', 'Online Bank', 'E-wallet')
  ),
  notes TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.financial_audit_expense_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  audit_id UUID NOT NULL REFERENCES public.financial_audits(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  category TEXT NOT NULL,
  amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
  payment_method TEXT NOT NULL DEFAULT 'Cash' CHECK (
    payment_method IN ('Cash', 'Online Bank', 'E-wallet')
  ),
  description TEXT NOT NULL DEFAULT '',
  vendor TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX financial_audits_organization_id_idx
  ON public.financial_audits(organization_id);
CREATE INDEX financial_audits_schedule_date_idx
  ON public.financial_audits(schedule_date DESC);
CREATE INDEX financial_audit_income_entries_audit_id_idx
  ON public.financial_audit_income_entries(audit_id);
CREATE INDEX financial_audit_income_entries_date_idx
  ON public.financial_audit_income_entries(date DESC);
CREATE INDEX financial_audit_expense_entries_audit_id_idx
  ON public.financial_audit_expense_entries(audit_id);
CREATE INDEX financial_audit_expense_entries_date_idx
  ON public.financial_audit_expense_entries(date DESC);
ALTER TABLE public.financial_audits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_audit_income_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_audit_expense_entries ENABLE ROW LEVEL SECURITY;
-- financial_audits policies
CREATE POLICY "Org members with financial module can view audits"
  ON public.financial_audits FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_audits.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_audits.organization_id, 'financial')
  );
CREATE POLICY "Org members with financial module can insert audits"
  ON public.financial_audits FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_audits.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_audits.organization_id, 'financial')
  );
CREATE POLICY "Org members with financial module can update audits"
  ON public.financial_audits FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_audits.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_audits.organization_id, 'financial')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_audits.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_audits.organization_id, 'financial')
  );
CREATE POLICY "Org admins with financial module can delete audits"
  ON public.financial_audits FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = financial_audits.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(financial_audits.organization_id, 'financial')
  );
-- financial_audit_income_entries policies
CREATE POLICY "Org members with financial module can view income entries"
  ON public.financial_audit_income_entries FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      JOIN public.organization_members om ON om.organization_id = fa.organization_id
      WHERE fa.id = financial_audit_income_entries.audit_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      WHERE fa.id = financial_audit_income_entries.audit_id
        AND public.org_has_module(fa.organization_id, 'financial')
    )
  );
CREATE POLICY "Org members with financial module can insert income entries"
  ON public.financial_audit_income_entries FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      JOIN public.organization_members om ON om.organization_id = fa.organization_id
      WHERE fa.id = financial_audit_income_entries.audit_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      WHERE fa.id = financial_audit_income_entries.audit_id
        AND public.org_has_module(fa.organization_id, 'financial')
    )
  );
CREATE POLICY "Org members with financial module can update income entries"
  ON public.financial_audit_income_entries FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      JOIN public.organization_members om ON om.organization_id = fa.organization_id
      WHERE fa.id = financial_audit_income_entries.audit_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      WHERE fa.id = financial_audit_income_entries.audit_id
        AND public.org_has_module(fa.organization_id, 'financial')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      JOIN public.organization_members om ON om.organization_id = fa.organization_id
      WHERE fa.id = financial_audit_income_entries.audit_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      WHERE fa.id = financial_audit_income_entries.audit_id
        AND public.org_has_module(fa.organization_id, 'financial')
    )
  );
CREATE POLICY "Org admins with financial module can delete income entries"
  ON public.financial_audit_income_entries FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      JOIN public.organization_members om ON om.organization_id = fa.organization_id
      WHERE fa.id = financial_audit_income_entries.audit_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      WHERE fa.id = financial_audit_income_entries.audit_id
        AND public.org_has_module(fa.organization_id, 'financial')
    )
  );
-- financial_audit_expense_entries policies
CREATE POLICY "Org members with financial module can view expense entries"
  ON public.financial_audit_expense_entries FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      JOIN public.organization_members om ON om.organization_id = fa.organization_id
      WHERE fa.id = financial_audit_expense_entries.audit_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      WHERE fa.id = financial_audit_expense_entries.audit_id
        AND public.org_has_module(fa.organization_id, 'financial')
    )
  );
CREATE POLICY "Org members with financial module can insert expense entries"
  ON public.financial_audit_expense_entries FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      JOIN public.organization_members om ON om.organization_id = fa.organization_id
      WHERE fa.id = financial_audit_expense_entries.audit_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      WHERE fa.id = financial_audit_expense_entries.audit_id
        AND public.org_has_module(fa.organization_id, 'financial')
    )
  );
CREATE POLICY "Org members with financial module can update expense entries"
  ON public.financial_audit_expense_entries FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      JOIN public.organization_members om ON om.organization_id = fa.organization_id
      WHERE fa.id = financial_audit_expense_entries.audit_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      WHERE fa.id = financial_audit_expense_entries.audit_id
        AND public.org_has_module(fa.organization_id, 'financial')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      JOIN public.organization_members om ON om.organization_id = fa.organization_id
      WHERE fa.id = financial_audit_expense_entries.audit_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      WHERE fa.id = financial_audit_expense_entries.audit_id
        AND public.org_has_module(fa.organization_id, 'financial')
    )
  );
CREATE POLICY "Org admins with financial module can delete expense entries"
  ON public.financial_audit_expense_entries FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      JOIN public.organization_members om ON om.organization_id = fa.organization_id
      WHERE fa.id = financial_audit_expense_entries.audit_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.financial_audits fa
      WHERE fa.id = financial_audit_expense_entries.audit_id
        AND public.org_has_module(fa.organization_id, 'financial')
    )
  );
