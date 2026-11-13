-- Self-contained community-feed authorization, trigger, moderation, and
-- notification coverage. Every fixture and state change is rolled back.
BEGIN;

INSERT INTO auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
('41000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','feed-admin-a@example.test','',now(),'{}','{}',now(),now()),
('41000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','feed-leader-a@example.test','',now(),'{}','{}',now(),now()),
('41000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','feed-member-a@example.test','',now(),'{}','{}',now(),now()),
('42000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','feed-admin-b@example.test','',now(),'{}','{}',now(),now());

INSERT INTO public.organizations(id,name,slug,plan,status) VALUES
('41000000-0000-0000-0000-000000000010','Feed Test A','feed-test-a','pro','active'),
('42000000-0000-0000-0000-000000000010','Feed Test B','feed-test-b','pro','active');
INSERT INTO public.subscriptions(organization_id,plan,plan_key,status) VALUES
('41000000-0000-0000-0000-000000000010','pro','pro','active'),
('42000000-0000-0000-0000-000000000010','pro','pro','active');
INSERT INTO public.organization_members(user_id,organization_id,role,status) VALUES
('41000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000010','admin','active'),
('42000000-0000-0000-0000-000000000001','42000000-0000-0000-0000-000000000010','admin','active');

ALTER TABLE public.people DISABLE TRIGGER enforce_people_limit_before_insert;
INSERT INTO public.people(id,organization_id,first_name,last_name,email,birthdate,status,membership_type,evangelism_stage) VALUES
('41000000-0000-0000-0000-000000000101','41000000-0000-0000-0000-000000000010','Feed','Leader','feed-leader-a@example.test','1990-01-01','Active','Member','Small Group'),
('41000000-0000-0000-0000-000000000102','41000000-0000-0000-0000-000000000010','Feed','Member','feed-member-a@example.test','1991-01-01','Active','Member','Small Group'),
('42000000-0000-0000-0000-000000000101','42000000-0000-0000-0000-000000000010','Other','Member','feed-admin-b@example.test','1992-01-01','Active','Member','Small Group');
ALTER TABLE public.people ENABLE TRIGGER enforce_people_limit_before_insert;

INSERT INTO public.circle_user_links(organization_id,user_id,person_id,status) VALUES
('41000000-0000-0000-0000-000000000010','41000000-0000-0000-0000-000000000002','41000000-0000-0000-0000-000000000101','active'),
('41000000-0000-0000-0000-000000000010','41000000-0000-0000-0000-000000000003','41000000-0000-0000-0000-000000000102','active'),
('42000000-0000-0000-0000-000000000010','42000000-0000-0000-0000-000000000001','42000000-0000-0000-0000-000000000101','active');

ALTER TABLE public.cell_groups DISABLE TRIGGER enforce_circle_leader_assignment;
INSERT INTO public.cell_groups(id,organization_id,name,description,location,leader_person_id,status) VALUES
('41000000-0000-0000-0000-000000000201','41000000-0000-0000-0000-000000000010','Feed Circle A','','','41000000-0000-0000-0000-000000000101','active'),
('41000000-0000-0000-0000-000000000202','41000000-0000-0000-0000-000000000010','Feed Circle Other','','','41000000-0000-0000-0000-000000000101','active'),
('42000000-0000-0000-0000-000000000201','42000000-0000-0000-0000-000000000010','Feed Circle B','','','42000000-0000-0000-0000-000000000101','active');
ALTER TABLE public.cell_groups ENABLE TRIGGER enforce_circle_leader_assignment;
ALTER TABLE public.cell_group_members DISABLE TRIGGER enforce_cell_leader_training_trigger;
INSERT INTO public.cell_group_members(cell_group_id,person_id,role) VALUES
('41000000-0000-0000-0000-000000000201','41000000-0000-0000-0000-000000000101','Leader'),
('41000000-0000-0000-0000-000000000201','41000000-0000-0000-0000-000000000102','Member'),
('41000000-0000-0000-0000-000000000202','41000000-0000-0000-0000-000000000101','Leader'),
('42000000-0000-0000-0000-000000000201','42000000-0000-0000-0000-000000000101','Leader');
ALTER TABLE public.cell_group_members ENABLE TRIGGER enforce_cell_leader_training_trigger;

INSERT INTO public.circle_feed_posts(id,organization_id,cell_group_id,author_person_id,audience,body) VALUES
('41000000-0000-0000-0000-000000000301','41000000-0000-0000-0000-000000000010',NULL,'41000000-0000-0000-0000-000000000102','organization','Organization fixture'),
('41000000-0000-0000-0000-000000000302','41000000-0000-0000-0000-000000000010','41000000-0000-0000-0000-000000000201','41000000-0000-0000-0000-000000000102','circle','Own Circle fixture'),
('41000000-0000-0000-0000-000000000303','41000000-0000-0000-0000-000000000010','41000000-0000-0000-0000-000000000202','41000000-0000-0000-0000-000000000101','circle','Other Circle fixture'),
('42000000-0000-0000-0000-000000000301','42000000-0000-0000-0000-000000000010',NULL,'42000000-0000-0000-0000-000000000101','organization','Other organization fixture');

INSERT INTO public.circle_prayer_requests(id,organization_id,cell_group_id,person_id,title,description,category,scope) VALUES
('41000000-0000-0000-0000-000000000304','41000000-0000-0000-0000-000000000010','41000000-0000-0000-0000-000000000201','41000000-0000-0000-0000-000000000102','Prayer journey fixture','Please pray with us.','Family','circle');

DO $$
DECLARE rejected BOOLEAN:=false; own_feed UUID;
BEGIN
  IF (SELECT count(*) FROM public.circle_feed_items WHERE source_type='post' AND source_id IN ('41000000-0000-0000-0000-000000000301','41000000-0000-0000-0000-000000000302','41000000-0000-0000-0000-000000000303','42000000-0000-0000-0000-000000000301'))<>4 THEN
    RAISE EXCEPTION 'Source triggers did not create one feed item per post';
  END IF;
  UPDATE public.circle_feed_posts SET body='Updated idempotently' WHERE id='41000000-0000-0000-0000-000000000301';
  IF (SELECT count(*) FROM public.circle_feed_items WHERE source_type='post' AND source_id='41000000-0000-0000-0000-000000000301')<>1 THEN
    RAISE EXCEPTION 'Post trigger is not idempotent';
  END IF;
  BEGIN
    UPDATE public.circle_feed_posts SET audience='circle',cell_group_id='41000000-0000-0000-0000-000000000201' WHERE id='41000000-0000-0000-0000-000000000301';
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Published post audience was mutable'; END IF;

  PERFORM set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000003',true);
  SET LOCAL ROLE authenticated;
  IF NOT EXISTS(SELECT 1 FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000301')
    OR NOT EXISTS(SELECT 1 FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000302')
    OR EXISTS(SELECT 1 FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000303')
    OR EXISTS(SELECT 1 FROM public.circle_feed_items WHERE source_id='42000000-0000-0000-0000-000000000301') THEN
    RAISE EXCEPTION 'Organization isolation or Circle audience boundary failed';
  END IF;
  rejected:=false;
  BEGIN PERFORM public.set_circle_feed_item_hidden((SELECT id FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000302'),true);
  EXCEPTION WHEN OTHERS THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'Ordinary member moderated a feed item'; END IF;
  RESET ROLE;

  SELECT id INTO own_feed FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000302';
  PERFORM set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.set_circle_feed_item_hidden(own_feed,true);
  RESET ROLE;
  IF NOT EXISTS(SELECT 1 FROM public.circle_feed_items WHERE id=own_feed AND hidden_at IS NOT NULL)
    OR NOT EXISTS(SELECT 1 FROM public.circle_feed_posts WHERE id='41000000-0000-0000-0000-000000000302') THEN
    RAISE EXCEPTION 'Leader moderation did not preserve the source record';
  END IF;

  INSERT INTO public.circle_feed_likes(feed_item_id,person_id) VALUES((SELECT id FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000301'),'41000000-0000-0000-0000-000000000101');
  IF NOT EXISTS(SELECT 1 FROM public.circle_feed_notifications WHERE recipient_person_id='41000000-0000-0000-0000-000000000102' AND kind='like' AND actor_count=1) THEN
    RAISE EXCEPTION 'Non-self activity did not create an aggregated notification';
  END IF;
  INSERT INTO public.circle_feed_likes(feed_item_id,person_id) VALUES((SELECT id FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000301'),'41000000-0000-0000-0000-000000000102');
  IF (SELECT count(*) FROM public.circle_feed_notifications WHERE recipient_person_id='41000000-0000-0000-0000-000000000102' AND kind='like')<>1 THEN
    RAISE EXCEPTION 'Self activity created a notification';
  END IF;

  -- New social interactions use authenticated, resource-authorized RPCs.
  PERFORM set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.set_circle_prayer_follow('41000000-0000-0000-0000-000000000304',true);
  PERFORM public.set_circle_feed_pinned((SELECT id FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000303'),true);
  RESET ROLE;

  PERFORM set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000003',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.upsert_circle_community_profile('Learning to serve faithfully.','shared_circle','hidden');
  PERFORM public.set_circle_feed_reaction((SELECT id FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000301'),'amen');
  PERFORM public.set_circle_feed_saved((SELECT id FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000301'),true);
  PERFORM public.add_circle_prayer_update('41000000-0000-0000-0000-000000000304','progress','The first appointment went well.');
  IF (public.get_circle_community_member_profile('41000000-0000-0000-0000-000000000102')->>'bio') IS DISTINCT FROM 'Learning to serve faithfully.' THEN
    RAISE EXCEPTION 'Owner could not read their profile';
  END IF;
  RESET ROLE;
  IF (SELECT count(*) FROM public.circle_feed_reactions WHERE feed_item_id=(SELECT id FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000301') AND person_id='41000000-0000-0000-0000-000000000102')<>1 THEN
    RAISE EXCEPTION 'Reaction uniqueness or authorization failed';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.circle_feed_saves WHERE person_id='41000000-0000-0000-0000-000000000102') THEN
    RAISE EXCEPTION 'Private save was not recorded';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM public.circle_feed_pins pin WHERE pin.feed_item_id=(SELECT id FROM public.circle_feed_items WHERE source_id='41000000-0000-0000-0000-000000000303')) THEN
    RAISE EXCEPTION 'Circle leader pin was not recorded';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.circle_feed_notifications notice WHERE notice.recipient_person_id='41000000-0000-0000-0000-000000000101' AND notice.kind='prayer_update') THEN
    RAISE EXCEPTION 'Prayer follower did not receive an update notification';
  END IF;
  IF (SELECT item.activity_at=(SELECT max(update_row.created_at) FROM public.circle_prayer_updates update_row WHERE update_row.prayer_id=item.source_id) FROM public.circle_feed_items item WHERE item.source_type='prayer' AND item.source_id='41000000-0000-0000-0000-000000000304') IS NOT TRUE THEN
    RAISE EXCEPTION 'Prayer update did not resurface its feed item';
  END IF;

  PERFORM set_config('request.jwt.claim.sub','42000000-0000-0000-0000-000000000001',true);
  SET LOCAL ROLE authenticated;
  IF public.get_circle_community_member_profile('41000000-0000-0000-0000-000000000102') IS NOT NULL THEN
    RAISE EXCEPTION 'Cross-organization profile disclosure detected';
  END IF;
  IF jsonb_array_length(public.search_circle_community_feed('Prayer journey fixture',NULL,NULL,NULL,false,50))<>0 THEN
    RAISE EXCEPTION 'Cross-organization feed search disclosure detected';
  END IF;
  RESET ROLE;

  UPDATE public.circle_user_links SET status='inactive' WHERE organization_id='41000000-0000-0000-0000-000000000010' AND user_id='41000000-0000-0000-0000-000000000003';
  PERFORM set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000003',true);
  SET LOCAL ROLE authenticated;
  IF EXISTS(SELECT 1 FROM public.circle_feed_items WHERE organization_id='41000000-0000-0000-0000-000000000010') THEN
    RAISE EXCEPTION 'Inactive member retained feed access';
  END IF;
  RESET ROLE;
END;
$$;

ROLLBACK;
