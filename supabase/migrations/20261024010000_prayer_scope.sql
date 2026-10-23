-- Add private Circle/organization audience selection to prayer requests.

ALTER TABLE public.circle_prayer_requests
  ADD COLUMN IF NOT EXISTS scope TEXT NOT NULL DEFAULT 'circle';

UPDATE public.circle_prayer_requests
SET scope = 'circle'
WHERE scope IS NULL;

ALTER TABLE public.circle_prayer_requests
  ALTER COLUMN scope SET DEFAULT 'circle',
  ALTER COLUMN scope SET NOT NULL,
  ALTER COLUMN cell_group_id DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'circle_prayer_requests_scope_check'
      AND conrelid = 'public.circle_prayer_requests'::regclass
  ) THEN
    ALTER TABLE public.circle_prayer_requests
      ADD CONSTRAINT circle_prayer_requests_scope_check
      CHECK (scope IN ('circle', 'organization'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'circle_prayer_requests_destination_check'
      AND conrelid = 'public.circle_prayer_requests'::regclass
  ) THEN
    ALTER TABLE public.circle_prayer_requests
      ADD CONSTRAINT circle_prayer_requests_destination_check
      CHECK (
        (scope = 'circle' AND cell_group_id IS NOT NULL)
        OR (scope = 'organization' AND cell_group_id IS NULL)
      );
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS circle_prayers_org_scope_created_idx
  ON public.circle_prayer_requests(organization_id, scope, created_at DESC);

CREATE OR REPLACE FUNCTION public.circle_has_active_org_access(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organization_members membership
    WHERE membership.organization_id = p_organization_id
      AND membership.user_id = auth.uid()
      AND membership.status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.circle_validate_prayer_destination()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND (
    NEW.organization_id IS DISTINCT FROM OLD.organization_id
    OR NEW.cell_group_id IS DISTINCT FROM OLD.cell_group_id
    OR NEW.person_id IS DISTINCT FROM OLD.person_id
    OR NEW.scope IS DISTINCT FROM OLD.scope
  ) THEN
    RAISE EXCEPTION 'A prayer audience cannot be changed after sharing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.people person
    WHERE person.id = NEW.person_id
      AND person.organization_id = NEW.organization_id
  ) THEN
    RAISE EXCEPTION 'Prayer author must belong to the organization';
  END IF;

  IF NEW.scope = 'circle' AND NOT EXISTS (
    SELECT 1
    FROM public.cell_groups group_row
    WHERE group_row.id = NEW.cell_group_id
      AND group_row.organization_id = NEW.organization_id
      AND group_row.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Prayer Circle must be active and belong to the organization';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS circle_prayer_requests_validate_destination
  ON public.circle_prayer_requests;
CREATE TRIGGER circle_prayer_requests_validate_destination
  BEFORE INSERT OR UPDATE ON public.circle_prayer_requests
  FOR EACH ROW EXECUTE FUNCTION public.circle_validate_prayer_destination();

DROP POLICY IF EXISTS "Circle members and admins read prayers"
  ON public.circle_prayer_requests;
DROP POLICY IF EXISTS "Circle members create prayers"
  ON public.circle_prayer_requests;
DROP POLICY IF EXISTS "Prayer authors leaders and admins update prayers"
  ON public.circle_prayer_requests;

CREATE POLICY "Prayer audiences read requests"
  ON public.circle_prayer_requests
  FOR SELECT TO authenticated
  USING (
    public.circle_has_active_org_access(organization_id)
    AND (
      scope = 'organization'
      OR (scope = 'circle' AND public.circle_can_access_group(cell_group_id))
    )
  );

CREATE POLICY "Members create scoped prayers"
  ON public.circle_prayer_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    public.circle_has_active_org_access(organization_id)
    AND person_id = public.circle_current_person_id(organization_id)
    AND (
      (scope = 'organization' AND cell_group_id IS NULL)
      OR (
        scope = 'circle'
        AND public.circle_can_access_group(cell_group_id)
        AND EXISTS (
          SELECT 1
          FROM public.cell_groups group_row
          WHERE group_row.id = cell_group_id
            AND group_row.organization_id = circle_prayer_requests.organization_id
        )
      )
    )
  );

CREATE POLICY "Authorized people answer prayers"
  ON public.circle_prayer_requests
  FOR UPDATE TO authenticated
  USING (
    public.circle_has_active_org_access(organization_id)
    AND (
      scope = 'organization'
      OR (scope = 'circle' AND public.circle_can_access_group(cell_group_id))
    )
    AND (
      person_id = public.circle_current_person_id(organization_id)
      OR public.circle_is_org_admin(organization_id)
      OR (scope = 'circle' AND public.circle_can_lead_group(cell_group_id))
    )
  )
  WITH CHECK (
    public.circle_has_active_org_access(organization_id)
    AND (
      person_id = public.circle_current_person_id(organization_id)
      OR public.circle_is_org_admin(organization_id)
      OR (scope = 'circle' AND public.circle_can_lead_group(cell_group_id))
    )
  );

DROP POLICY IF EXISTS "Circle members read prayer clicks"
  ON public.circle_prayer_clicks;
DROP POLICY IF EXISTS "Circle members add own prayer click"
  ON public.circle_prayer_clicks;
DROP POLICY IF EXISTS "Circle members remove own prayer click"
  ON public.circle_prayer_clicks;

CREATE POLICY "Prayer audiences read prayer clicks"
  ON public.circle_prayer_clicks
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.circle_prayer_requests prayer
      WHERE prayer.id = prayer_id
        AND public.circle_has_active_org_access(prayer.organization_id)
        AND (
          prayer.scope = 'organization'
          OR public.circle_can_access_group(prayer.cell_group_id)
        )
    )
  );

CREATE POLICY "Prayer audiences add own prayer click"
  ON public.circle_prayer_clicks
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.circle_prayer_requests prayer
      WHERE prayer.id = prayer_id
        AND prayer.organization_id = circle_prayer_clicks.organization_id
        AND public.circle_has_active_org_access(prayer.organization_id)
        AND circle_prayer_clicks.person_id = public.circle_current_person_id(prayer.organization_id)
        AND (
          prayer.scope = 'organization'
          OR public.circle_can_access_group(prayer.cell_group_id)
        )
    )
  );

CREATE POLICY "Prayer audiences remove own prayer click"
  ON public.circle_prayer_clicks
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.circle_prayer_requests prayer
      WHERE prayer.id = prayer_id
        AND prayer.organization_id = circle_prayer_clicks.organization_id
        AND public.circle_has_active_org_access(prayer.organization_id)
        AND circle_prayer_clicks.person_id = public.circle_current_person_id(prayer.organization_id)
        AND (
          prayer.scope = 'organization'
          OR public.circle_can_access_group(prayer.cell_group_id)
        )
    )
  );

CREATE OR REPLACE FUNCTION public.get_circle_prayers(
  p_cell_group_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_organization_id UUID;
  v_person_id UUID;
  result JSONB;
BEGIN
  SELECT membership.organization_id
  INTO v_organization_id
  FROM public.organization_members membership
  WHERE membership.user_id = auth.uid()
    AND membership.status = 'active'
  ORDER BY (membership.role = 'admin') DESC, membership.created_at
  LIMIT 1;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  v_person_id := public.circle_current_person_id(v_organization_id);

  IF p_cell_group_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.cell_groups group_row
    WHERE group_row.id = p_cell_group_id
      AND group_row.organization_id = v_organization_id
      AND group_row.status = 'active'
      AND public.circle_can_access_group(group_row.id)
  ) THEN
    RAISE EXCEPTION 'Circle access required';
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', prayer.id,
        'groupId', prayer.cell_group_id,
        'scope', prayer.scope,
        'destinationName', CASE
          WHEN prayer.scope = 'organization' THEN 'Entire organization'
          ELSE group_row.name
        END,
        'userId', prayer.person_id,
        'authorName', concat_ws(' ', person.first_name, person.last_name),
        'title', prayer.title,
        'description', prayer.description,
        'category', prayer.category,
        'isAnswered', prayer.is_answered,
        'answeredNotes', prayer.answered_notes,
        'createdAt', prayer.created_at,
        'prayerCount', (
          SELECT count(*)
          FROM public.circle_prayer_clicks click
          WHERE click.prayer_id = prayer.id
        ),
        'prayedByMe', EXISTS (
          SELECT 1
          FROM public.circle_prayer_clicks click
          WHERE click.prayer_id = prayer.id
            AND click.person_id = v_person_id
        )
      )
      ORDER BY prayer.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO result
  FROM public.circle_prayer_requests prayer
  LEFT JOIN public.cell_groups group_row ON group_row.id = prayer.cell_group_id
  LEFT JOIN public.people person ON person.id = prayer.person_id
  WHERE prayer.organization_id = v_organization_id
    AND (
      prayer.scope = 'organization'
      OR (
        p_cell_group_id IS NOT NULL
        AND prayer.scope = 'circle'
        AND prayer.cell_group_id = p_cell_group_id
      )
    );

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_circle_prayers(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_circle_prayers(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.circle_has_active_org_access(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.circle_has_active_org_access(UUID) TO authenticated;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.circle_prayer_requests
    WHERE scope <> 'circle' OR cell_group_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Existing prayers were not preserved as Circle-scoped';
  END IF;
END;
$$;
