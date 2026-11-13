-- Administrative positions and organization leadership (head pastor, ministry heads)

CREATE TABLE public.admin_positions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  appointed_date DATE NOT NULL DEFAULT CURRENT_DATE,
  term TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.organization_leadership (
  organization_id UUID PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
  head_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.work_ministries
  ADD COLUMN head_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL;
CREATE INDEX admin_positions_organization_id_idx ON public.admin_positions(organization_id);
CREATE INDEX admin_positions_person_id_idx ON public.admin_positions(person_id);
CREATE INDEX admin_positions_status_idx ON public.admin_positions(status);
CREATE INDEX work_ministries_head_person_id_idx ON public.work_ministries(head_person_id);
ALTER TABLE public.admin_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_leadership ENABLE ROW LEVEL SECURITY;
-- admin_positions policies
CREATE POLICY "Org members can view admin positions"
  ON public.admin_positions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = admin_positions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert admin positions"
  ON public.admin_positions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = admin_positions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update admin positions"
  ON public.admin_positions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = admin_positions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = admin_positions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can delete admin positions"
  ON public.admin_positions FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = admin_positions.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
-- organization_leadership policies
CREATE POLICY "Org members can view organization leadership"
  ON public.organization_leadership FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = organization_leadership.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can insert organization leadership"
  ON public.organization_leadership FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = organization_leadership.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
CREATE POLICY "Org members can update organization leadership"
  ON public.organization_leadership FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = organization_leadership.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = organization_leadership.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
  );
