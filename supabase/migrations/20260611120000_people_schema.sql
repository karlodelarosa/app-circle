-- Households scoped to an organization (SaaS tenant)
CREATE TABLE public.households (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX households_organization_id_idx ON public.households(organization_id);
CREATE TYPE public.person_membership_type AS ENUM (
  'Worker',
  'Member',
  'Attender',
  'For Evangelism',
  'Prospect'
);
CREATE TYPE public.person_evangelism_stage AS ENUM (
  'First-time Attendee',
  'Follow-up',
  'Small Group',
  'Discipleship',
  'Worker'
);
-- People scoped to an organization
CREATE TABLE public.people (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE RESTRICT,
  first_name TEXT NOT NULL,
  middle_name TEXT,
  last_name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  birthdate DATE NOT NULL,
  role TEXT NOT NULL DEFAULT 'Single' CHECK (role IN ('Head', 'Spouse', 'Child', 'Single', 'Other')),
  status TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Inactive', 'Exited')),
  membership_type public.person_membership_type NOT NULL DEFAULT 'Attender',
  evangelism_stage public.person_evangelism_stage NOT NULL DEFAULT 'First-time Attendee',
  is_prospect BOOLEAN NOT NULL DEFAULT false,
  join_date DATE NOT NULL DEFAULT CURRENT_DATE,
  last_attendance DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX people_organization_id_idx ON public.people(organization_id);
CREATE INDEX people_household_id_idx ON public.people(household_id);
CREATE INDEX people_organization_name_idx ON public.people(organization_id, last_name, first_name);
ALTER TABLE public.households ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.people ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members can view households"
  ON public.households FOR SELECT
  USING (public.is_org_member(organization_id));
CREATE POLICY "Org members can insert households"
  ON public.households FOR INSERT
  WITH CHECK (public.is_org_member(organization_id));
CREATE POLICY "Org members can update households"
  ON public.households FOR UPDATE
  USING (public.is_org_member(organization_id))
  WITH CHECK (public.is_org_member(organization_id));
CREATE POLICY "Org admins can delete households"
  ON public.households FOR DELETE
  USING (public.is_org_admin(organization_id));
CREATE POLICY "Org members can view people"
  ON public.people FOR SELECT
  USING (public.is_org_member(organization_id));
CREATE POLICY "Org members can insert people"
  ON public.people FOR INSERT
  WITH CHECK (public.is_org_member(organization_id));
CREATE POLICY "Org members can update people"
  ON public.people FOR UPDATE
  USING (public.is_org_member(organization_id))
  WITH CHECK (public.is_org_member(organization_id));
CREATE POLICY "Org admins can delete people"
  ON public.people FOR DELETE
  USING (public.is_org_admin(organization_id));
