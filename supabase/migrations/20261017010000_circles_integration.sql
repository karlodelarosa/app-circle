-- Circles is the member-facing companion to SheepCount cell groups.
-- SheepCount remains the source of truth for organizations, people, groups,
-- memberships, and recorded attendance.

-- Circles is a Pro feature. Per-organization feature overrides continue to win
-- through the existing entitlement resolver.
UPDATE public.subscription_plans
SET features = jsonb_set(COALESCE(features, '{}'::jsonb), '{circles_access}', 'false'::jsonb, true)
WHERE key = 'basic';
UPDATE public.subscription_plans
SET features = jsonb_set(COALESCE(features, '{}'::jsonb), '{circles_access}', 'true'::jsonb, true)
WHERE key = 'pro';
CREATE TABLE public.circle_user_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, user_id),
  UNIQUE (organization_id, person_id)
);
CREATE TABLE public.circle_access_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID NOT NULL REFERENCES public.cell_groups(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  requested_by UUID NOT NULL REFERENCES auth.users(id),
  approved_by UUID REFERENCES auth.users(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'accepted', 'rejected', 'cancelled')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_at TIMESTAMPTZ,
  accepted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX circle_access_requests_open_idx
  ON public.circle_access_requests (organization_id, person_id)
  WHERE status IN ('pending', 'approved');
CREATE TABLE public.circle_gatherings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID NOT NULL REFERENCES public.cell_groups(id) ON DELETE CASCADE,
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
  starts_at TIMESTAMPTZ NOT NULL,
  location TEXT NOT NULL DEFAULT '',
  study_topic TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'cancelled', 'completed')),
  leader_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  attendance_session_id UUID REFERENCES public.cell_group_sessions(id) ON DELETE SET NULL,
  checkin_code TEXT UNIQUE,
  checkin_opened_at TIMESTAMPTZ,
  checkin_closes_at TIMESTAMPTZ,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.circle_gathering_rsvps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gathering_id UUID NOT NULL REFERENCES public.circle_gatherings(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('attending', 'tentative', 'declined')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (gathering_id, person_id)
);
CREATE TABLE public.circle_prayer_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID NOT NULL REFERENCES public.cell_groups(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 100),
  description TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 800),
  category TEXT NOT NULL DEFAULT 'Other' CHECK (category IN ('Family', 'Work or School', 'Health', 'Spiritual Growth', 'Other')),
  is_answered BOOLEAN NOT NULL DEFAULT false,
  answered_notes TEXT CHECK (char_length(answered_notes) <= 800),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.circle_prayer_clicks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prayer_id UUID NOT NULL REFERENCES public.circle_prayer_requests(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (prayer_id, person_id)
);
CREATE INDEX circle_user_links_user_idx ON public.circle_user_links(user_id) WHERE status = 'active';
CREATE INDEX circle_access_requests_group_idx ON public.circle_access_requests(cell_group_id, status);
CREATE INDEX circle_gatherings_group_date_idx ON public.circle_gatherings(cell_group_id, starts_at);
CREATE INDEX circle_gathering_rsvps_gathering_idx ON public.circle_gathering_rsvps(gathering_id);
CREATE INDEX circle_prayers_group_created_idx ON public.circle_prayer_requests(cell_group_id, created_at DESC);
CREATE INDEX circle_prayer_clicks_prayer_idx ON public.circle_prayer_clicks(prayer_id);
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_user_links_set_updated_at
  BEFORE UPDATE ON public.circle_user_links
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER circle_access_requests_set_updated_at
  BEFORE UPDATE ON public.circle_access_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER circle_gatherings_set_updated_at
  BEFORE UPDATE ON public.circle_gatherings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER circle_gathering_rsvps_set_updated_at
  BEFORE UPDATE ON public.circle_gathering_rsvps
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER circle_prayer_requests_set_updated_at
  BEFORE UPDATE ON public.circle_prayer_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE OR REPLACE FUNCTION public.circle_org_enabled(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT COALESCE((
      SELECT (resolved.features ->> 'circles_access')::boolean
      FROM public.get_org_subscription_row(p_organization_id) resolved
    ), false)
    AND EXISTS (
      SELECT 1 FROM public.organizations o
      WHERE o.id = p_organization_id AND o.status = 'active'
    );
$$;
CREATE OR REPLACE FUNCTION public.circle_is_org_admin(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.organization_id = p_organization_id
      AND om.user_id = auth.uid()
      AND om.role = 'admin'
      AND om.status = 'active'
  );
$$;
CREATE OR REPLACE FUNCTION public.circle_current_person_id(p_organization_id UUID)
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT cul.person_id
  FROM public.circle_user_links cul
  WHERE cul.organization_id = p_organization_id
    AND cul.user_id = auth.uid()
    AND cul.status = 'active'
  LIMIT 1;
$$;
CREATE OR REPLACE FUNCTION public.circle_can_access_group(p_cell_group_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.cell_groups cg
    WHERE cg.id = p_cell_group_id
      AND public.circle_org_enabled(cg.organization_id)
      AND (
        public.circle_is_org_admin(cg.organization_id)
        OR EXISTS (
          SELECT 1
          FROM public.circle_user_links cul
          JOIN public.cell_group_members cgm ON cgm.person_id = cul.person_id
          WHERE cul.organization_id = cg.organization_id
            AND cul.user_id = auth.uid()
            AND cul.status = 'active'
            AND cgm.cell_group_id = cg.id
        )
      )
  );
$$;
CREATE OR REPLACE FUNCTION public.circle_can_lead_group(p_cell_group_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.cell_groups cg
    WHERE cg.id = p_cell_group_id
      AND public.circle_org_enabled(cg.organization_id)
      AND (
        public.circle_is_org_admin(cg.organization_id)
        OR EXISTS (
          SELECT 1
          FROM public.circle_user_links cul
          LEFT JOIN public.cell_group_members cgm
            ON cgm.person_id = cul.person_id AND cgm.cell_group_id = cg.id
          WHERE cul.organization_id = cg.organization_id
            AND cul.user_id = auth.uid()
            AND cul.status = 'active'
            AND (cgm.role = 'Leader' OR cg.leader_person_id = cul.person_id)
        )
      )
  );
$$;
ALTER TABLE public.circle_user_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_access_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_gatherings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_gathering_rsvps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_prayer_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_prayer_clicks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Circle users read own links" ON public.circle_user_links
  FOR SELECT TO authenticated USING (
    user_id = auth.uid() OR public.circle_is_org_admin(organization_id)
  );
CREATE POLICY "Circle admins manage links" ON public.circle_user_links
  FOR ALL TO authenticated USING (public.circle_is_org_admin(organization_id))
  WITH CHECK (public.circle_is_org_admin(organization_id));
CREATE POLICY "Circle leaders and admins read access requests" ON public.circle_access_requests
  FOR SELECT TO authenticated USING (
    public.circle_can_lead_group(cell_group_id)
  );
CREATE POLICY "Circle members read gatherings" ON public.circle_gatherings
  FOR SELECT TO authenticated USING (public.circle_can_access_group(cell_group_id));
CREATE POLICY "Circle leaders create gatherings" ON public.circle_gatherings
  FOR INSERT TO authenticated WITH CHECK (
    public.circle_can_lead_group(cell_group_id)
    AND public.circle_org_enabled(organization_id)
    AND created_by = auth.uid()
  );
CREATE POLICY "Circle leaders update gatherings" ON public.circle_gatherings
  FOR UPDATE TO authenticated USING (public.circle_can_lead_group(cell_group_id))
  WITH CHECK (public.circle_can_lead_group(cell_group_id));
CREATE POLICY "Circle members read RSVPs" ON public.circle_gathering_rsvps
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.circle_gatherings cg WHERE cg.id = gathering_id AND public.circle_can_access_group(cg.cell_group_id))
  );
CREATE POLICY "Circle members create own RSVP" ON public.circle_gathering_rsvps
  FOR INSERT TO authenticated WITH CHECK (
    public.circle_can_access_group((SELECT cell_group_id FROM public.circle_gatherings WHERE id = gathering_id))
    AND
    person_id = public.circle_current_person_id((SELECT organization_id FROM public.circle_gatherings WHERE id = gathering_id))
  );
CREATE POLICY "Circle members update own RSVP" ON public.circle_gathering_rsvps
  FOR UPDATE TO authenticated USING (
    public.circle_can_access_group((SELECT cell_group_id FROM public.circle_gatherings WHERE id = gathering_id))
    AND
    person_id = public.circle_current_person_id((SELECT organization_id FROM public.circle_gatherings WHERE id = gathering_id))
  ) WITH CHECK (
    public.circle_can_access_group((SELECT cell_group_id FROM public.circle_gatherings WHERE id = gathering_id))
    AND
    person_id = public.circle_current_person_id((SELECT organization_id FROM public.circle_gatherings WHERE id = gathering_id))
  );
CREATE POLICY "Circle members and admins read prayers" ON public.circle_prayer_requests
  FOR SELECT TO authenticated USING (public.circle_can_access_group(cell_group_id));
CREATE POLICY "Circle members create prayers" ON public.circle_prayer_requests
  FOR INSERT TO authenticated WITH CHECK (
    public.circle_can_access_group(cell_group_id)
    AND person_id = public.circle_current_person_id(organization_id)
  );
CREATE POLICY "Prayer authors leaders and admins update prayers" ON public.circle_prayer_requests
  FOR UPDATE TO authenticated USING (
    public.circle_can_access_group(cell_group_id)
    AND (person_id = public.circle_current_person_id(organization_id) OR public.circle_can_lead_group(cell_group_id))
  ) WITH CHECK (
    public.circle_can_access_group(cell_group_id)
    AND (person_id = public.circle_current_person_id(organization_id) OR public.circle_can_lead_group(cell_group_id))
  );
CREATE POLICY "Circle members read prayer clicks" ON public.circle_prayer_clicks
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.circle_prayer_requests cpr WHERE cpr.id = prayer_id AND public.circle_can_access_group(cpr.cell_group_id))
  );
CREATE POLICY "Circle members add own prayer click" ON public.circle_prayer_clicks
  FOR INSERT TO authenticated WITH CHECK (
    public.circle_can_access_group((SELECT cell_group_id FROM public.circle_prayer_requests WHERE id = prayer_id))
    AND
    person_id = public.circle_current_person_id((SELECT organization_id FROM public.circle_prayer_requests WHERE id = prayer_id))
  );
CREATE POLICY "Circle members remove own prayer click" ON public.circle_prayer_clicks
  FOR DELETE TO authenticated USING (
    public.circle_can_access_group((SELECT cell_group_id FROM public.circle_prayer_requests WHERE id = prayer_id))
    AND
    person_id = public.circle_current_person_id((SELECT organization_id FROM public.circle_prayer_requests WHERE id = prayer_id))
  );
-- Extend SheepCount RLS narrowly for authenticated Circles members. Organization
-- admins already receive access through the existing SheepCount policies.
CREATE POLICY "Circle users view their organization" ON public.organizations
  FOR SELECT TO authenticated USING (
    public.circle_org_enabled(id) AND EXISTS (
      SELECT 1 FROM public.circle_user_links cul
      WHERE cul.organization_id = organizations.id AND cul.user_id = auth.uid() AND cul.status = 'active'
    )
  );
CREATE POLICY "Circle users view their groups" ON public.cell_groups
  FOR SELECT TO authenticated USING (public.circle_can_access_group(id));
CREATE POLICY "Circle users view their memberships" ON public.cell_group_members
  FOR SELECT TO authenticated USING (public.circle_can_access_group(cell_group_id));
CREATE POLICY "Circle leaders add group members" ON public.cell_group_members
  FOR INSERT TO authenticated WITH CHECK (
    public.circle_can_lead_group(cell_group_id)
    AND EXISTS (
      SELECT 1 FROM public.people p JOIN public.cell_groups cg ON cg.organization_id = p.organization_id
      WHERE p.id = person_id AND cg.id = cell_group_id
    )
  );
CREATE POLICY "Circle leaders remove group members" ON public.cell_group_members
  FOR DELETE TO authenticated USING (public.circle_can_lead_group(cell_group_id));
CREATE POLICY "Circle leaders update their group" ON public.cell_groups
  FOR UPDATE TO authenticated USING (public.circle_can_lead_group(id))
  WITH CHECK (public.circle_can_lead_group(id));
CREATE POLICY "Circle users view people in their group" ON public.people
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.cell_group_members cgm
      WHERE cgm.person_id = people.id AND public.circle_can_access_group(cgm.cell_group_id)
    )
  );
CREATE POLICY "Circle users view linked attendance sessions" ON public.cell_group_sessions
  FOR SELECT TO authenticated USING (public.circle_can_access_group(cell_group_id));
CREATE POLICY "Circle users view linked attendance attendees" ON public.cell_group_session_attendees
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.cell_group_sessions cgs WHERE cgs.id = session_id AND public.circle_can_access_group(cgs.cell_group_id))
  );
CREATE OR REPLACE FUNCTION public.get_my_circle_context()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_org_id UUID;
  v_person_id UUID;
  v_is_admin BOOLEAN := false;
  v_result JSONB;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  SELECT om.organization_id, true INTO v_org_id, v_is_admin
  FROM public.organization_members om
  WHERE om.user_id = v_user_id AND om.status = 'active' AND om.role = 'admin'
  ORDER BY om.created_at LIMIT 1;

  IF v_org_id IS NULL THEN
    SELECT cul.organization_id, cul.person_id INTO v_org_id, v_person_id
    FROM public.circle_user_links cul
    WHERE cul.user_id = v_user_id AND cul.status = 'active'
    ORDER BY cul.created_at LIMIT 1;
  END IF;

  IF v_org_id IS NOT NULL AND v_person_id IS NULL THEN
    SELECT cul.person_id INTO v_person_id
    FROM public.circle_user_links cul
    WHERE cul.organization_id = v_org_id AND cul.user_id = v_user_id AND cul.status = 'active'
    LIMIT 1;
  END IF;

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'No Circles access has been approved for this account'; END IF;

  SELECT jsonb_build_object(
    'organization', jsonb_build_object('id', o.id, 'name', o.name, 'image', o.image, 'status', o.status),
    'circlesEnabled', public.circle_org_enabled(o.id),
    'isAdmin', v_is_admin,
    'personId', v_person_id,
    'profile', jsonb_build_object('id', p.id, 'firstName', p.first_name, 'lastName', p.last_name, 'avatarUrl', p.avatar_url),
    'groups', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cg.id,
        'name', cg.name,
        'description', cg.description,
        'location', cg.location,
        'leaderPersonId', cg.leader_person_id,
        'status', cg.status,
        'role', CASE
          WHEN v_is_admin THEN 'admin'
          WHEN cgm.role = 'Leader' OR cg.leader_person_id = v_person_id THEN 'leader'
          ELSE 'member'
        END
      ) ORDER BY cg.name)
      FROM public.cell_groups cg
      LEFT JOIN public.cell_group_members cgm ON cgm.cell_group_id = cg.id AND cgm.person_id = v_person_id
      WHERE cg.organization_id = o.id
        AND cg.status = 'active'
        AND (v_is_admin OR cgm.id IS NOT NULL)
    ), '[]'::jsonb)
  ) INTO v_result
  FROM public.organizations o
  LEFT JOIN public.profiles p ON p.id = v_user_id
  WHERE o.id = v_org_id;

  RETURN v_result;
END;
$$;
CREATE OR REPLACE FUNCTION public.create_circle_group(
  p_name TEXT,
  p_description TEXT DEFAULT '',
  p_location TEXT DEFAULT '',
  p_leader_person_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_org_id UUID; v_group_id UUID;
BEGIN
  SELECT organization_id INTO v_org_id FROM public.organization_members
  WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active' ORDER BY created_at LIMIT 1;
  IF v_org_id IS NULL OR NOT public.circle_org_enabled(v_org_id) THEN RAISE EXCEPTION 'Circles Pro access is required'; END IF;
  IF nullif(trim(p_name), '') IS NULL THEN RAISE EXCEPTION 'Group name is required'; END IF;
  IF p_leader_person_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.people WHERE id = p_leader_person_id AND organization_id = v_org_id) THEN
    RAISE EXCEPTION 'Leader does not belong to this organization';
  END IF;
  INSERT INTO public.cell_groups (organization_id, name, description, location, leader_person_id)
  VALUES (v_org_id, trim(p_name), trim(p_description), trim(p_location), p_leader_person_id)
  RETURNING id INTO v_group_id;
  IF p_leader_person_id IS NOT NULL THEN
    INSERT INTO public.cell_group_members (cell_group_id, person_id, role)
    VALUES (v_group_id, p_leader_person_id, 'Leader') ON CONFLICT (cell_group_id, person_id) DO UPDATE SET role = 'Leader';
  END IF;
  RETURN v_group_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.request_circle_access(p_cell_group_id UUID, p_person_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_org_id UUID; v_request_id UUID;
BEGIN
  SELECT organization_id INTO v_org_id FROM public.cell_groups WHERE id = p_cell_group_id;
  IF NOT public.circle_can_lead_group(p_cell_group_id) THEN RAISE EXCEPTION 'Only the assigned leader or an organization admin can request access'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cell_group_members WHERE cell_group_id = p_cell_group_id AND person_id = p_person_id) THEN
    RAISE EXCEPTION 'Add this person to the cell group before requesting access';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.people WHERE id = p_person_id AND organization_id = v_org_id AND email <> '') THEN
    RAISE EXCEPTION 'This person needs an email address before access can be requested';
  END IF;
  INSERT INTO public.circle_access_requests (organization_id, cell_group_id, person_id, requested_by)
  VALUES (v_org_id, p_cell_group_id, p_person_id, auth.uid())
  ON CONFLICT (organization_id, person_id) WHERE status IN ('pending', 'approved')
  DO UPDATE SET cell_group_id = excluded.cell_group_id, requested_by = excluded.requested_by, status = 'pending', approved_by = NULL, approved_at = NULL
  RETURNING id INTO v_request_id;
  RETURN v_request_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.approve_circle_access(p_request_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_org_id UUID; v_email TEXT;
BEGIN
  SELECT car.organization_id, p.email INTO v_org_id, v_email
  FROM public.circle_access_requests car JOIN public.people p ON p.id = car.person_id
  WHERE car.id = p_request_id AND car.status = 'pending';
  IF v_org_id IS NULL OR NOT public.circle_is_org_admin(v_org_id) THEN RAISE EXCEPTION 'Only an organization admin can approve access'; END IF;
  IF NOT public.circle_org_enabled(v_org_id) THEN RAISE EXCEPTION 'Circles Pro access is required'; END IF;
  UPDATE public.circle_access_requests SET status = 'approved', approved_by = auth.uid(), approved_at = now() WHERE id = p_request_id;
  RETURN v_email;
END;
$$;
CREATE OR REPLACE FUNCTION public.accept_circle_access()
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_request public.circle_access_requests%ROWTYPE; v_email TEXT; v_link_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  v_email := lower(COALESCE(auth.jwt() ->> 'email', ''));
  SELECT car.* INTO v_request
  FROM public.circle_access_requests car JOIN public.people p ON p.id = car.person_id
  WHERE car.status = 'approved' AND lower(p.email) = v_email
  ORDER BY car.approved_at DESC LIMIT 1;
  IF v_request.id IS NULL THEN RAISE EXCEPTION 'No approved Circles invitation matches this email'; END IF;
  IF NOT public.circle_org_enabled(v_request.organization_id) THEN RAISE EXCEPTION 'Circles Pro access is required'; END IF;
  INSERT INTO public.circle_user_links (organization_id, user_id, person_id)
  VALUES (v_request.organization_id, auth.uid(), v_request.person_id)
  ON CONFLICT (organization_id, user_id) DO UPDATE SET person_id = excluded.person_id, status = 'active', updated_at = now()
  RETURNING id INTO v_link_id;
  UPDATE public.circle_access_requests SET status = 'accepted', accepted_at = now() WHERE id = v_request.id;
  RETURN v_link_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.open_circle_checkin(p_gathering_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_gathering public.circle_gatherings%ROWTYPE;
  v_group public.cell_groups%ROWTYPE;
  v_code TEXT;
  v_session_id UUID;
  v_leader_name TEXT;
BEGIN
  SELECT * INTO v_gathering FROM public.circle_gatherings WHERE id = p_gathering_id AND status = 'scheduled';
  IF v_gathering.id IS NULL OR NOT public.circle_can_lead_group(v_gathering.cell_group_id) THEN RAISE EXCEPTION 'Only a circle leader can open check-in'; END IF;
  SELECT * INTO v_group FROM public.cell_groups WHERE id = v_gathering.cell_group_id;
  LOOP
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.circle_gatherings WHERE checkin_code = v_code);
  END LOOP;
  SELECT concat_ws(' ', p.first_name, p.last_name) INTO v_leader_name
  FROM public.people p WHERE p.id = COALESCE(v_gathering.leader_person_id, v_group.leader_person_id);
  v_leader_name := COALESCE(nullif(v_leader_name, ''), 'Cell Group leader');

  INSERT INTO public.cell_group_sessions (
    organization_id, cell_group_id, session_date, leader_person_id, leader_name, location
  ) VALUES (
    v_gathering.organization_id, v_gathering.cell_group_id, (v_gathering.starts_at AT TIME ZONE 'UTC')::date,
    COALESCE(v_gathering.leader_person_id, v_group.leader_person_id), v_leader_name, v_gathering.location
  ) ON CONFLICT (cell_group_id, session_date) DO UPDATE
    SET leader_person_id = excluded.leader_person_id, leader_name = excluded.leader_name,
        location = excluded.location, updated_at = now()
  RETURNING id INTO v_session_id;

  UPDATE public.circle_gatherings SET
    checkin_code = v_code,
    checkin_opened_at = now(),
    checkin_closes_at = now() + interval '6 hours',
    attendance_session_id = v_session_id
  WHERE id = p_gathering_id;
  RETURN v_code;
END;
$$;
CREATE OR REPLACE FUNCTION public.close_circle_checkin(p_gathering_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_group_id UUID;
BEGIN
  SELECT cell_group_id INTO v_group_id FROM public.circle_gatherings WHERE id = p_gathering_id;
  IF v_group_id IS NULL OR NOT public.circle_can_lead_group(v_group_id) THEN RAISE EXCEPTION 'Only a circle leader can close check-in'; END IF;
  UPDATE public.circle_gatherings SET checkin_code = NULL, checkin_closes_at = now() WHERE id = p_gathering_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.get_circle_checkin_context(p_code TEXT)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'organizationName', o.name,
    'organizationImage', o.image,
    'groupName', cg.name,
    'gatheringTitle', g.title,
    'startsAt', g.starts_at
  )
  FROM public.circle_gatherings g
  JOIN public.cell_groups cg ON cg.id = g.cell_group_id
  JOIN public.organizations o ON o.id = g.organization_id
  WHERE g.checkin_code = upper(trim(p_code))
    AND g.checkin_opened_at IS NOT NULL
    AND g.checkin_closes_at > now()
    AND g.status = 'scheduled'
    AND public.circle_org_enabled(g.organization_id)
  LIMIT 1;
$$;
CREATE OR REPLACE FUNCTION public.guest_circle_checkin(
  p_code TEXT,
  p_first_name TEXT,
  p_last_name TEXT,
  p_phone TEXT DEFAULT '',
  p_social_contact TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_gathering public.circle_gatherings%ROWTYPE;
  v_group public.cell_groups%ROWTYPE;
  v_person_id UUID;
  v_session_id UUID;
  v_leader_name TEXT;
  v_inserted_count INT := 0;
BEGIN
  IF nullif(trim(p_first_name), '') IS NULL OR nullif(trim(p_last_name), '') IS NULL THEN RAISE EXCEPTION 'First and last name are required'; END IF;
  IF nullif(trim(p_phone), '') IS NULL AND nullif(trim(p_social_contact), '') IS NULL THEN RAISE EXCEPTION 'Add a phone number or social contact'; END IF;
  SELECT * INTO v_gathering FROM public.circle_gatherings
  WHERE checkin_code = upper(trim(p_code)) AND checkin_opened_at IS NOT NULL AND checkin_closes_at > now() AND status = 'scheduled';
  IF v_gathering.id IS NULL OR NOT public.circle_org_enabled(v_gathering.organization_id) THEN RAISE EXCEPTION 'This check-in code is invalid or has expired'; END IF;
  SELECT * INTO v_group FROM public.cell_groups WHERE id = v_gathering.cell_group_id;

  SELECT id INTO v_person_id FROM public.people
  WHERE organization_id = v_gathering.organization_id
    AND ((trim(p_phone) <> '' AND phone = trim(p_phone)) OR (trim(p_social_contact) <> '' AND lower(social_contact) = lower(trim(p_social_contact))))
  ORDER BY created_at LIMIT 1;
  IF v_person_id IS NULL THEN
    INSERT INTO public.people (
      organization_id, household_id, first_name, last_name, phone, social_contact,
      email, birthdate, role, status, membership_type, evangelism_stage,
      is_prospect, join_date, first_attendance
    ) VALUES (
      v_gathering.organization_id, NULL, trim(p_first_name), trim(p_last_name), trim(p_phone), trim(p_social_contact),
      '', NULL, 'Single', 'Active', 'Prospect', 'Small Group', true, current_date, current_date
    ) RETURNING id INTO v_person_id;
  END IF;

  SELECT concat_ws(' ', p.first_name, p.last_name) INTO v_leader_name
  FROM public.people p WHERE p.id = COALESCE(v_gathering.leader_person_id, v_group.leader_person_id);
  v_leader_name := COALESCE(nullif(v_leader_name, ''), 'Cell Group leader');

  INSERT INTO public.cell_group_sessions (
    organization_id, cell_group_id, session_date, leader_person_id, leader_name, location
  ) VALUES (
    v_gathering.organization_id, v_gathering.cell_group_id, (v_gathering.starts_at AT TIME ZONE 'UTC')::date,
    COALESCE(v_gathering.leader_person_id, v_group.leader_person_id), v_leader_name, v_gathering.location
  ) ON CONFLICT (cell_group_id, session_date) DO UPDATE
    SET leader_person_id = excluded.leader_person_id, leader_name = excluded.leader_name,
        location = excluded.location, updated_at = now()
  RETURNING id INTO v_session_id;

  INSERT INTO public.cell_group_session_attendees (session_id, person_id)
  VALUES (v_session_id, v_person_id) ON CONFLICT (session_id, person_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted_count = ROW_COUNT;
  UPDATE public.circle_gatherings SET attendance_session_id = v_session_id WHERE id = v_gathering.id;

  RETURN jsonb_build_object('ok', true, 'alreadyRecorded', v_inserted_count = 0);
END;
$$;
REVOKE ALL ON FUNCTION public.circle_org_enabled(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.circle_is_org_admin(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.circle_current_person_id(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.circle_can_access_group(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.circle_can_lead_group(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_circle_context() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_circle_group(TEXT, TEXT, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_circle_access(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_circle_access(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_circle_access() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.open_circle_checkin(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.close_circle_checkin(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_circle_checkin_context(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guest_circle_checkin(TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_circle_context() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_circle_group(TEXT, TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_circle_access(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_circle_access(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_circle_access() TO authenticated;
GRANT EXECUTE ON FUNCTION public.open_circle_checkin(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_circle_checkin(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_circle_checkin_context(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guest_circle_checkin(TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.circle_org_enabled(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.circle_is_org_admin(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.circle_current_person_id(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.circle_can_access_group(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.circle_can_lead_group(UUID) TO authenticated;
