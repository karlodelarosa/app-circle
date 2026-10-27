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
  v_gathering_id UUID;
  v_organization_gathering_id UUID;
  v_guest_rsvp_id UUID;
  v_signup_id UUID;
  v_signup_person_id UUID;
  v_signup_phone TEXT := '+639' || lpad((floor(random() * 1000000000))::BIGINT::TEXT, 9, '0');
  v_organization_slug TEXT;
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
  ) RETURNING id INTO v_gathering_id;

  INSERT INTO public.circle_public_spaces (organization_id, is_published)
  VALUES (v_organization_id, true)
  ON CONFLICT (organization_id) DO UPDATE SET is_published = true;

  SELECT slug INTO v_organization_slug FROM public.organizations WHERE id=v_organization_id;
  PERFORM public.submit_circle_group_signup(
    v_organization_slug,
    'Signup',
    'Smoke Test',
    DATE '1998-06-14',
    v_signup_phone,
    '',
    true,
    NULL
  );

  SELECT signup.id,signup.person_id INTO v_signup_id,v_signup_person_id
  FROM public.circle_group_signups signup
  JOIN public.people person ON person.id=signup.person_id
  WHERE signup.organization_id=v_organization_id
    AND signup.status='unassigned' AND person.phone=v_signup_phone;

  IF v_signup_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.people
    WHERE id=v_signup_person_id AND status='Active' AND membership_type='Prospect'
      AND is_prospect AND evangelism_stage='Small Group' AND birthdate=DATE '1998-06-14'
  ) THEN
    RAISE EXCEPTION 'Official signup did not create an unassigned Prospect';
  END IF;

  -- A repeated exact-contact submission refreshes the same queue item.
  PERFORM public.submit_circle_group_signup(
    v_organization_slug,'Signup','Smoke Test',DATE '1998-06-14',
    v_signup_phone,'',true,NULL
  );
  IF (SELECT count(*) FROM public.circle_group_signups
      WHERE organization_id=v_organization_id AND person_id=v_signup_person_id AND status='unassigned') <> 1 THEN
    RAISE EXCEPTION 'Repeated official signup created a duplicate queue item';
  END IF;
  IF public.get_circle_group_signup_attention_count(v_organization_id) < 1 OR NOT (
    public.get_circle_group_signups(v_organization_id,'unassigned') @>
    jsonb_build_array(jsonb_build_object('id',v_signup_id))
  ) THEN
    RAISE EXCEPTION 'Official signup is missing from the shared leader queue';
  END IF;

  PERFORM public.place_circle_group_signup(v_signup_id,v_group_id);
  IF NOT EXISTS (
    SELECT 1 FROM public.cell_group_members
    WHERE cell_group_id=v_group_id AND person_id=v_signup_person_id
  ) OR NOT EXISTS (
    SELECT 1 FROM public.circle_group_signups
    WHERE id=v_signup_id AND status='placed' AND placed_cell_group_id=v_group_id
  ) OR NOT EXISTS (
    SELECT 1 FROM public.people
    WHERE id=v_signup_person_id AND membership_type='Prospect' AND is_prospect
  ) THEN
    RAISE EXCEPTION 'Official signup placement contract failed';
  END IF;

  INSERT INTO public.circle_gatherings (
    organization_id, cell_group_id, scope, title, starts_at, location,
    study_topic, notes, summary, visibility, guest_rsvp_enabled,
    public_slug, published_at, created_by
  ) VALUES (
    v_organization_id, NULL, 'organization', 'Organization RSVP smoke test',
    now() + interval '1 day', 'Test location', '', '', 'Rolled back automatically.',
    'public', true, 'organization-smoke-' || v_suffix, now(), auth.uid()
  ) RETURNING id INTO v_organization_gathering_id;

  v_guest_rsvp_id := (
    public.submit_circle_guest_rsvp(
      v_gathering_id,
      'Circle Guest',
      'circle-guest-' || v_suffix || '@example.com',
      '',
      'attending'
    )->>'id'
  )::UUID;

  IF NOT EXISTS (
    SELECT 1 FROM public.circle_guest_rsvps WHERE id = v_guest_rsvp_id
  ) THEN
    RAISE EXCEPTION 'Circle gathering guest RSVP is not visible to its manager';
  END IF;

  IF v_person_id IS NOT NULL THEN
    INSERT INTO public.circle_gathering_rsvps (
      organization_id, gathering_id, person_id, status
    ) VALUES (
      v_organization_id, v_gathering_id, v_person_id, 'attending'
    )
    ON CONFLICT (gathering_id, person_id) DO UPDATE SET status='tentative';

    IF (
      SELECT status FROM public.circle_gathering_rsvps
      WHERE gathering_id=v_gathering_id AND person_id=v_person_id
    ) <> 'tentative' THEN
      RAISE EXCEPTION 'Authenticated member RSVP upsert did not update the existing response';
    END IF;

    INSERT INTO public.circle_gathering_rsvps (
      organization_id, gathering_id, person_id, status
    ) VALUES (
      v_organization_id, v_organization_gathering_id, v_person_id, 'attending'
    )
    ON CONFLICT (gathering_id, person_id) DO UPDATE SET status='tentative';

    IF (
      SELECT status FROM public.circle_gathering_rsvps
      WHERE gathering_id=v_organization_gathering_id AND person_id=v_person_id
    ) <> 'tentative' THEN
      RAISE EXCEPTION 'Organization gathering member RSVP upsert did not update the response';
    END IF;
  END IF;

  PERFORM public.record_circle_attendance(
    v_gathering_id,
    ARRAY[]::UUID[],
    ARRAY[v_guest_rsvp_id]
  );

  IF (SELECT status FROM public.circle_gatherings WHERE id = v_gathering_id) <> 'scheduled' THEN
    RAISE EXCEPTION 'Saving attendance must not complete a gathering';
  END IF;

  IF NOT COALESCE((public.get_circle_gathering_attendance(v_gathering_id)->>'saved')::BOOLEAN,false) THEN
    RAISE EXCEPTION 'Saved attendance could not be reloaded';
  END IF;

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
