-- Run against a linked non-production or explicitly approved project.
-- Every write is rolled back; this verifies the authenticated admin contracts.
BEGIN;

SELECT set_config(
  'request.jwt.claim.sub',
  (
    SELECT user_id::text
    FROM public.organization_members
    WHERE role = 'admin' AND status = 'active'
    ORDER BY created_at
    LIMIT 1
  ),
  true
);

SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_context JSONB := public.get_my_circle_context();
  v_organization_id UUID := (v_context->'organization'->>'id')::UUID;
  v_group_id UUID := (v_context->'groups'->0->>'id')::UUID;
  v_suffix TEXT := replace(gen_random_uuid()::text, '-', '');
  v_gallery_id UUID;
  v_person_id UUID := (v_context->>'personId')::UUID;
  v_circle_prayer_id UUID;
  v_organization_prayer_id UUID;
BEGIN
  IF v_organization_id IS NULL OR v_group_id IS NULL THEN
    RAISE EXCEPTION 'Smoke test requires an active admin organization with a Circle';
  END IF;

  PERFORM public.search_circle_people(v_organization_id, v_group_id, 'a');
  PERFORM public.register_circle_visitor(
    v_group_id,
    'Circles',
    'Smoke Test',
    'circles-smoke-' || v_suffix || '@example.com',
    '',
    NULL
  );

  INSERT INTO public.circle_announcements (
    organization_id, cell_group_id, title, body, created_by
  ) VALUES (
    v_organization_id, v_group_id, 'Circles smoke test', 'Rolled back automatically.', auth.uid()
  );

  INSERT INTO public.circle_testimonies (
    organization_id, cell_group_id, author_display_name, public_slug,
    title, body, status, published_at, created_by
  ) VALUES (
    v_organization_id, v_group_id, 'Circles test', 'smoke-' || v_suffix,
    'Circles smoke test', 'Rolled back automatically.', 'published', now(), auth.uid()
  );

  INSERT INTO public.circle_galleries (
    organization_id, cell_group_id, public_slug, title, description,
    status, published_at, created_by
  ) VALUES (
    v_organization_id, v_group_id, 'smoke-' || v_suffix,
    'Circles smoke test', 'Rolled back automatically.', 'published', now(), auth.uid()
  ) RETURNING id INTO v_gallery_id;

  INSERT INTO public.circle_gatherings (
    organization_id, cell_group_id, title, starts_at, location,
    study_topic, notes, summary, visibility, guest_rsvp_enabled,
    public_slug, published_at, created_by
  ) VALUES (
    v_organization_id, v_group_id, 'Circles smoke test', now() + interval '1 day',
    'Test location', '', '', 'Rolled back automatically.', 'public', true,
    'smoke-' || v_suffix, now(), auth.uid()
  );

  IF v_person_id IS NOT NULL THEN
    INSERT INTO public.circle_prayer_requests (
      organization_id, cell_group_id, person_id, scope, title, description, category
    ) VALUES (
      v_organization_id, v_group_id, v_person_id, 'circle',
      'Circle prayer smoke test', 'Rolled back automatically.', 'Other'
    ) RETURNING id INTO v_circle_prayer_id;

    INSERT INTO public.circle_prayer_requests (
      organization_id, cell_group_id, person_id, scope, title, description, category
    ) VALUES (
      v_organization_id, NULL, v_person_id, 'organization',
      'Organization prayer smoke test', 'Rolled back automatically.', 'Other'
    ) RETURNING id INTO v_organization_prayer_id;

    IF NOT (
      public.get_circle_prayers(v_group_id) @>
      jsonb_build_array(
        jsonb_build_object('id', v_circle_prayer_id),
        jsonb_build_object('id', v_organization_prayer_id)
      )
    ) THEN
      RAISE EXCEPTION 'Scoped prayer read contract did not return both audiences';
    END IF;
  END IF;
END;
$$;

ROLLBACK;
