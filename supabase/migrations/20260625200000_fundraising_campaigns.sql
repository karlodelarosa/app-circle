-- Fundraising campaigns (goal_projects module)

CREATE TABLE public.fundraising_campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT 'Other',
  goal_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (goal_amount >= 0),
  target_date DATE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed')),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.fundraising_contributions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id UUID NOT NULL REFERENCES public.fundraising_campaigns(id) ON DELETE CASCADE,
  person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  contributed_on DATE NOT NULL,
  payment_method TEXT NOT NULL DEFAULT 'Cash' CHECK (
    payment_method IN ('Cash', 'Online Bank', 'E-wallet')
  ),
  notes TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX fundraising_campaigns_organization_id_idx
  ON public.fundraising_campaigns(organization_id);
CREATE INDEX fundraising_campaigns_status_idx
  ON public.fundraising_campaigns(status);
CREATE INDEX fundraising_campaigns_target_date_idx
  ON public.fundraising_campaigns(target_date DESC);
CREATE INDEX fundraising_contributions_campaign_id_idx
  ON public.fundraising_contributions(campaign_id);
CREATE INDEX fundraising_contributions_person_id_idx
  ON public.fundraising_contributions(person_id);
CREATE INDEX fundraising_contributions_contributed_on_idx
  ON public.fundraising_contributions(contributed_on DESC);
ALTER TABLE public.fundraising_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fundraising_contributions ENABLE ROW LEVEL SECURITY;
-- fundraising_campaigns policies
CREATE POLICY "Org members with goal_projects module can view fundraising campaigns"
  ON public.fundraising_campaigns FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = fundraising_campaigns.organization_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND public.org_has_module(fundraising_campaigns.organization_id, 'goal_projects')
  );
CREATE POLICY "Org admins with goal_projects module can insert fundraising campaigns"
  ON public.fundraising_campaigns FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = fundraising_campaigns.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(fundraising_campaigns.organization_id, 'goal_projects')
  );
CREATE POLICY "Org admins with goal_projects module can update fundraising campaigns"
  ON public.fundraising_campaigns FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = fundraising_campaigns.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(fundraising_campaigns.organization_id, 'goal_projects')
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = fundraising_campaigns.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(fundraising_campaigns.organization_id, 'goal_projects')
  );
CREATE POLICY "Org admins with goal_projects module can delete fundraising campaigns"
  ON public.fundraising_campaigns FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = fundraising_campaigns.organization_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND public.org_has_module(fundraising_campaigns.organization_id, 'goal_projects')
  );
-- fundraising_contributions policies
CREATE POLICY "Org members with goal_projects module can view fundraising contributions"
  ON public.fundraising_contributions FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.fundraising_campaigns fc
      JOIN public.organization_members om ON om.organization_id = fc.organization_id
      WHERE fc.id = fundraising_contributions.campaign_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.fundraising_campaigns fc
      WHERE fc.id = fundraising_contributions.campaign_id
        AND public.org_has_module(fc.organization_id, 'goal_projects')
    )
  );
CREATE POLICY "Org members with goal_projects module can insert fundraising contributions"
  ON public.fundraising_contributions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.fundraising_campaigns fc
      JOIN public.organization_members om ON om.organization_id = fc.organization_id
      WHERE fc.id = fundraising_contributions.campaign_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.fundraising_campaigns fc
      WHERE fc.id = fundraising_contributions.campaign_id
        AND public.org_has_module(fc.organization_id, 'goal_projects')
    )
  );
CREATE POLICY "Org members with goal_projects module can update fundraising contributions"
  ON public.fundraising_contributions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.fundraising_campaigns fc
      JOIN public.organization_members om ON om.organization_id = fc.organization_id
      WHERE fc.id = fundraising_contributions.campaign_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.fundraising_campaigns fc
      WHERE fc.id = fundraising_contributions.campaign_id
        AND public.org_has_module(fc.organization_id, 'goal_projects')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.fundraising_campaigns fc
      JOIN public.organization_members om ON om.organization_id = fc.organization_id
      WHERE fc.id = fundraising_contributions.campaign_id
        AND om.user_id = auth.uid()
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.fundraising_campaigns fc
      WHERE fc.id = fundraising_contributions.campaign_id
        AND public.org_has_module(fc.organization_id, 'goal_projects')
    )
  );
CREATE POLICY "Org admins with goal_projects module can delete fundraising contributions"
  ON public.fundraising_contributions FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.fundraising_campaigns fc
      JOIN public.organization_members om ON om.organization_id = fc.organization_id
      WHERE fc.id = fundraising_contributions.campaign_id
        AND om.user_id = auth.uid()
        AND om.role = 'admin'
        AND om.status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.fundraising_campaigns fc
      WHERE fc.id = fundraising_contributions.campaign_id
        AND public.org_has_module(fc.organization_id, 'goal_projects')
    )
  );
