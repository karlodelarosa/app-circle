-- Include every active Circle a person belongs to or leads. Direct leader
-- assignment does not require a duplicate cell_group_members row.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_circle_context()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_org UUID;
  v_person UUID;
  v_admin BOOLEAN := false;
  v_result JSONB;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT om.organization_id, (om.role = 'admin')
  INTO v_org, v_admin
  FROM public.organization_members om
  WHERE om.user_id = v_user AND om.status = 'active'
  ORDER BY (om.role = 'admin') DESC, om.created_at
  LIMIT 1;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'No active SheepCount organization is linked to this account';
  END IF;

  SELECT cul.person_id
  INTO v_person
  FROM public.circle_user_links cul
  WHERE cul.organization_id = v_org
    AND cul.user_id = v_user
    AND cul.status = 'active'
  LIMIT 1;

  SELECT jsonb_build_object(
    'organization', jsonb_build_object(
      'id', o.id,
      'name', o.name,
      'slug', o.slug,
      'image', o.image,
      'status', o.status
    ),
    'circlesEnabled', true,
    'isAdmin', v_admin,
    'personId', v_person,
    'profile', jsonb_build_object(
      'id', p.id,
      'firstName', p.first_name,
      'lastName', p.last_name,
      'avatarUrl', p.avatar_url
    ),
    'groups', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', cg.id,
          'name', cg.name,
          'description', cg.description,
          'location', cg.location,
          'leaderPersonId', cg.leader_person_id,
          'status', cg.status,
          'role', CASE
            WHEN v_admin THEN 'admin'
            WHEN cgm.role = 'Leader' OR cg.leader_person_id = v_person THEN 'leader'
            ELSE 'member'
          END
        ) ORDER BY cg.name
      )
      FROM public.cell_groups cg
      LEFT JOIN public.cell_group_members cgm
        ON cgm.cell_group_id = cg.id AND cgm.person_id = v_person
      WHERE cg.organization_id = o.id
        AND cg.status = 'active'
        AND (
          v_admin
          OR cgm.id IS NOT NULL
          OR cg.leader_person_id = v_person
        )
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM public.organizations o
  LEFT JOIN public.profiles p ON p.id = v_user
  WHERE o.id = v_org;

  RETURN v_result;
END;
$$;

COMMIT;
