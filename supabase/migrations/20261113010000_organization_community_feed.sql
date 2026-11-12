BEGIN;

CREATE TABLE public.circle_feed_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE CASCADE,
  author_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  audience TEXT NOT NULL DEFAULT 'organization' CHECK (audience IN ('organization','circle')),
  body TEXT NOT NULL DEFAULT '' CHECK (char_length(body) <= 5000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((audience='organization' AND cell_group_id IS NULL) OR (audience='circle' AND cell_group_id IS NOT NULL))
);

CREATE TABLE public.circle_feed_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE CASCADE,
  origin_cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE CASCADE,
  audience TEXT NOT NULL CHECK (audience IN ('organization','circle')),
  source_type TEXT NOT NULL CHECK (source_type IN ('post','reflection','prayer','gathering','announcement')),
  source_id UUID NOT NULL,
  author_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL,
  hidden_at TIMESTAMPTZ,
  hidden_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  UNIQUE(source_type,source_id),
  CHECK ((audience='organization' AND cell_group_id IS NULL) OR (audience='circle' AND cell_group_id IS NOT NULL))
);
CREATE INDEX circle_feed_items_page_idx ON public.circle_feed_items(organization_id,created_at DESC,id DESC) WHERE hidden_at IS NULL;
CREATE INDEX circle_feed_items_circle_page_idx ON public.circle_feed_items(cell_group_id,created_at DESC,id DESC) WHERE hidden_at IS NULL;

CREATE TABLE public.circle_feed_post_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES public.circle_feed_posts(id) ON DELETE CASCADE,
  storage_path TEXT NOT NULL UNIQUE CHECK (char_length(storage_path) BETWEEN 10 AND 500),
  alt_text TEXT NOT NULL CHECK (char_length(btrim(alt_text)) BETWEEN 1 AND 300),
  display_order SMALLINT NOT NULL CHECK (display_order BETWEEN 0 AND 3),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(post_id,display_order)
);

CREATE TABLE public.circle_feed_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feed_item_id UUID NOT NULL REFERENCES public.circle_feed_items(id) ON DELETE CASCADE,
  author_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 2000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX circle_feed_comments_item_idx ON public.circle_feed_comments(feed_item_id,created_at,id);

CREATE TABLE public.circle_feed_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feed_item_id UUID NOT NULL REFERENCES public.circle_feed_items(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(feed_item_id,person_id)
);

CREATE TABLE public.circle_feed_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  recipient_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  feed_item_id UUID NOT NULL REFERENCES public.circle_feed_items(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('comment','like','pray')),
  latest_actor_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  actor_count INTEGER NOT NULL DEFAULT 1 CHECK (actor_count > 0),
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(recipient_person_id,feed_item_id,kind)
);
CREATE INDEX circle_feed_notifications_recipient_idx ON public.circle_feed_notifications(recipient_person_id,updated_at DESC);

ALTER TABLE public.circle_gathering_reflections
  ADD COLUMN scope TEXT,
  ADD COLUMN cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE CASCADE;
UPDATE public.circle_gathering_reflections reflection
SET scope='circle',cell_group_id=gathering.cell_group_id
FROM public.circle_gatherings gathering
WHERE gathering.id=reflection.gathering_id;
ALTER TABLE public.circle_gathering_reflections
  ALTER COLUMN scope SET DEFAULT 'organization',
  ALTER COLUMN scope SET NOT NULL;
ALTER TABLE public.circle_gathering_reflections
  ADD CONSTRAINT circle_gathering_reflections_scope_check CHECK (scope IN ('organization','circle')),
  ADD CONSTRAINT circle_gathering_reflections_destination_check CHECK ((scope='organization' AND cell_group_id IS NULL) OR (scope='circle' AND cell_group_id IS NOT NULL));

CREATE OR REPLACE FUNCTION public.circle_feed_item_visible(p_feed_item_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.circle_feed_items item
    WHERE item.id=p_feed_item_id AND item.hidden_at IS NULL
      AND public.circle_has_active_org_access(item.organization_id)
      AND (item.audience='organization' OR public.circle_can_access_group(item.cell_group_id))
  );
$$;

CREATE OR REPLACE FUNCTION public.circle_feed_item_moderatable(p_feed_item_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.circle_feed_items item
    WHERE item.id=p_feed_item_id
      AND (public.circle_is_org_admin(item.organization_id) OR (coalesce(item.origin_cell_group_id,item.cell_group_id) IS NOT NULL AND public.circle_can_lead_group(coalesce(item.origin_cell_group_id,item.cell_group_id))))
  );
$$;

CREATE OR REPLACE FUNCTION public.circle_validate_feed_post()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  NEW.body:=btrim(NEW.body);
  IF NEW.body='' AND NOT EXISTS(SELECT 1 FROM public.circle_feed_post_photos photo WHERE photo.post_id=NEW.id) AND TG_OP='UPDATE' THEN
    RAISE EXCEPTION 'A feed post requires text or a photo';
  END IF;
  IF TG_OP='UPDATE' THEN
    IF NEW.organization_id<>OLD.organization_id OR NEW.author_person_id<>OLD.author_person_id OR NEW.audience<>OLD.audience OR NEW.cell_group_id IS DISTINCT FROM OLD.cell_group_id OR NEW.created_at<>OLD.created_at THEN
      RAISE EXCEPTION 'Feed post ownership and audience cannot be changed';
    END IF;
    NEW.updated_at:=now();
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.people person WHERE person.id=NEW.author_person_id AND person.organization_id=NEW.organization_id) THEN
    RAISE EXCEPTION 'Feed post author must belong to the organization';
  END IF;
  IF NEW.audience='circle' AND NOT EXISTS(SELECT 1 FROM public.cell_groups group_row WHERE group_row.id=NEW.cell_group_id AND group_row.organization_id=NEW.organization_id AND group_row.status='active') THEN
    RAISE EXCEPTION 'Feed post Circle must be active and belong to the organization';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_feed_posts_validate BEFORE INSERT OR UPDATE ON public.circle_feed_posts FOR EACH ROW EXECUTE FUNCTION public.circle_validate_feed_post();

CREATE OR REPLACE FUNCTION public.circle_validate_reflection_feed_scope()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE gathering public.circle_gatherings%ROWTYPE;
BEGIN
  SELECT * INTO gathering FROM public.circle_gatherings WHERE id=NEW.gathering_id;
  IF TG_OP='UPDATE' AND (NEW.scope<>OLD.scope OR NEW.cell_group_id IS DISTINCT FROM OLD.cell_group_id) THEN
    RAISE EXCEPTION 'A reflection audience cannot be changed after sharing';
  END IF;
  IF NEW.scope='circle' AND NEW.cell_group_id IS DISTINCT FROM gathering.cell_group_id THEN
    RAISE EXCEPTION 'A Circle reflection must use its gathering Circle';
  END IF;
  IF NEW.scope='organization' THEN NEW.cell_group_id:=NULL; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_gathering_reflections_feed_scope BEFORE INSERT OR UPDATE ON public.circle_gathering_reflections FOR EACH ROW EXECUTE FUNCTION public.circle_validate_reflection_feed_scope();

CREATE OR REPLACE FUNCTION public.circle_sync_feed_post()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF TG_OP='DELETE' THEN DELETE FROM public.circle_feed_items WHERE source_type='post' AND source_id=OLD.id; RETURN OLD; END IF;
  INSERT INTO public.circle_feed_items(organization_id,cell_group_id,origin_cell_group_id,audience,source_type,source_id,author_person_id,created_at)
  VALUES(NEW.organization_id,NEW.cell_group_id,NEW.cell_group_id,NEW.audience,'post',NEW.id,NEW.author_person_id,NEW.created_at)
  ON CONFLICT(source_type,source_id) DO UPDATE SET cell_group_id=excluded.cell_group_id,origin_cell_group_id=excluded.origin_cell_group_id,audience=excluded.audience,author_person_id=excluded.author_person_id;
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_feed_posts_sync AFTER INSERT OR UPDATE OR DELETE ON public.circle_feed_posts FOR EACH ROW EXECUTE FUNCTION public.circle_sync_feed_post();

CREATE OR REPLACE FUNCTION public.circle_sync_feed_reflection()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE origin_group UUID;
BEGIN
  IF TG_OP='DELETE' THEN DELETE FROM public.circle_feed_items WHERE source_type='reflection' AND source_id=OLD.id; RETURN OLD; END IF;
  SELECT gathering.cell_group_id INTO origin_group FROM public.circle_gatherings gathering WHERE gathering.id=NEW.gathering_id;
  INSERT INTO public.circle_feed_items(organization_id,cell_group_id,origin_cell_group_id,audience,source_type,source_id,author_person_id,created_at)
  VALUES(NEW.organization_id,NEW.cell_group_id,origin_group,NEW.scope,'reflection',NEW.id,NEW.author_person_id,NEW.created_at)
  ON CONFLICT(source_type,source_id) DO UPDATE SET cell_group_id=excluded.cell_group_id,origin_cell_group_id=excluded.origin_cell_group_id,audience=excluded.audience,author_person_id=excluded.author_person_id;
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_feed_reflections_sync AFTER INSERT OR UPDATE OR DELETE ON public.circle_gathering_reflections FOR EACH ROW EXECUTE FUNCTION public.circle_sync_feed_reflection();

CREATE OR REPLACE FUNCTION public.circle_sync_feed_prayer()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF TG_OP='DELETE' THEN DELETE FROM public.circle_feed_items WHERE source_type='prayer' AND source_id=OLD.id; RETURN OLD; END IF;
  INSERT INTO public.circle_feed_items(organization_id,cell_group_id,origin_cell_group_id,audience,source_type,source_id,author_person_id,created_at)
  VALUES(NEW.organization_id,NEW.cell_group_id,NEW.cell_group_id,NEW.scope,'prayer',NEW.id,NEW.person_id,NEW.created_at)
  ON CONFLICT(source_type,source_id) DO UPDATE SET cell_group_id=excluded.cell_group_id,origin_cell_group_id=excluded.origin_cell_group_id,audience=excluded.audience,author_person_id=excluded.author_person_id;
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_feed_prayers_sync AFTER INSERT OR UPDATE OR DELETE ON public.circle_prayer_requests FOR EACH ROW EXECUTE FUNCTION public.circle_sync_feed_prayer();

CREATE OR REPLACE FUNCTION public.circle_sync_feed_gathering()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE author_id UUID;
BEGIN
  IF TG_OP='DELETE' THEN DELETE FROM public.circle_feed_items WHERE source_type='gathering' AND source_id=OLD.id; RETURN OLD; END IF;
  IF NEW.status<>'scheduled' OR NEW.assignment_confirmed_at IS NULL THEN DELETE FROM public.circle_feed_items WHERE source_type='gathering' AND source_id=NEW.id; RETURN NEW; END IF;
  SELECT link.person_id INTO author_id FROM public.circle_user_links link WHERE link.organization_id=NEW.organization_id AND link.user_id=NEW.created_by AND link.status='active' LIMIT 1;
  INSERT INTO public.circle_feed_items(organization_id,cell_group_id,origin_cell_group_id,audience,source_type,source_id,author_person_id,created_at)
  VALUES(NEW.organization_id,NEW.cell_group_id,NEW.cell_group_id,CASE WHEN NEW.scope='organization' THEN 'organization' ELSE 'circle' END,'gathering',NEW.id,author_id,NEW.created_at)
  ON CONFLICT(source_type,source_id) DO UPDATE SET cell_group_id=excluded.cell_group_id,origin_cell_group_id=excluded.origin_cell_group_id,audience=excluded.audience,author_person_id=excluded.author_person_id;
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_feed_gatherings_sync AFTER INSERT OR UPDATE OR DELETE ON public.circle_gatherings FOR EACH ROW EXECUTE FUNCTION public.circle_sync_feed_gathering();

CREATE OR REPLACE FUNCTION public.circle_sync_feed_announcement()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE author_id UUID;
BEGIN
  IF TG_OP='DELETE' THEN DELETE FROM public.circle_feed_items WHERE source_type='announcement' AND source_id=OLD.id; RETURN OLD; END IF;
  IF NEW.assignment_confirmed_at IS NULL THEN DELETE FROM public.circle_feed_items WHERE source_type='announcement' AND source_id=NEW.id; RETURN NEW; END IF;
  SELECT link.person_id INTO author_id FROM public.circle_user_links link WHERE link.organization_id=NEW.organization_id AND link.user_id=NEW.created_by AND link.status='active' LIMIT 1;
  INSERT INTO public.circle_feed_items(organization_id,cell_group_id,origin_cell_group_id,audience,source_type,source_id,author_person_id,created_at)
  VALUES(NEW.organization_id,NEW.cell_group_id,NEW.cell_group_id,CASE WHEN NEW.cell_group_id IS NULL THEN 'organization' ELSE 'circle' END,'announcement',NEW.id,author_id,NEW.published_at)
  ON CONFLICT(source_type,source_id) DO UPDATE SET cell_group_id=excluded.cell_group_id,origin_cell_group_id=excluded.origin_cell_group_id,audience=excluded.audience,author_person_id=excluded.author_person_id;
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_feed_announcements_sync AFTER INSERT OR UPDATE OR DELETE ON public.circle_announcements FOR EACH ROW EXECUTE FUNCTION public.circle_sync_feed_announcement();

CREATE OR REPLACE FUNCTION public.circle_limit_feed_photos()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF (SELECT count(*) FROM public.circle_feed_post_photos photo WHERE photo.post_id=NEW.post_id)>=4 THEN RAISE EXCEPTION 'A feed post can contain at most four photos'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.circle_feed_posts post WHERE post.id=NEW.post_id AND post.organization_id=NEW.organization_id) THEN RAISE EXCEPTION 'Feed photo and post organization must match'; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_feed_photos_limit BEFORE INSERT ON public.circle_feed_post_photos FOR EACH ROW EXECUTE FUNCTION public.circle_limit_feed_photos();

CREATE OR REPLACE FUNCTION public.circle_prepare_feed_comment()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN NEW.body:=btrim(NEW.body); IF TG_OP='UPDATE' THEN NEW.updated_at:=now(); END IF; RETURN NEW; END;
$$;
CREATE TRIGGER circle_feed_comments_prepare BEFORE INSERT OR UPDATE ON public.circle_feed_comments FOR EACH ROW EXECUTE FUNCTION public.circle_prepare_feed_comment();

CREATE OR REPLACE FUNCTION public.circle_notify_feed_activity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE; recipient UUID; activity_kind TEXT; actor UUID;
BEGIN
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  IF TG_TABLE_NAME='circle_feed_comments' THEN activity_kind:='comment'; actor:=NEW.author_person_id; SELECT * INTO item FROM public.circle_feed_items WHERE id=NEW.feed_item_id;
  ELSIF TG_TABLE_NAME='circle_feed_likes' THEN activity_kind:='like'; actor:=NEW.person_id; SELECT * INTO item FROM public.circle_feed_items WHERE id=NEW.feed_item_id;
  ELSE activity_kind:='pray'; actor:=NEW.person_id; SELECT feed.* INTO item FROM public.circle_feed_items feed WHERE feed.source_type='prayer' AND feed.source_id=NEW.prayer_id; END IF;
  recipient:=item.author_person_id;
  IF recipient IS NULL OR recipient=actor THEN RETURN NEW; END IF;
  INSERT INTO public.circle_feed_notifications(organization_id,recipient_person_id,feed_item_id,kind,latest_actor_person_id)
  VALUES(item.organization_id,recipient,item.id,activity_kind,actor)
  ON CONFLICT(recipient_person_id,feed_item_id,kind) DO UPDATE SET latest_actor_person_id=excluded.latest_actor_person_id,actor_count=circle_feed_notifications.actor_count+1,read_at=NULL,updated_at=now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_feed_comments_notify AFTER INSERT ON public.circle_feed_comments FOR EACH ROW EXECUTE FUNCTION public.circle_notify_feed_activity();
CREATE TRIGGER circle_feed_likes_notify AFTER INSERT ON public.circle_feed_likes FOR EACH ROW EXECUTE FUNCTION public.circle_notify_feed_activity();
CREATE TRIGGER circle_feed_prays_notify AFTER INSERT ON public.circle_prayer_clicks FOR EACH ROW EXECUTE FUNCTION public.circle_notify_feed_activity();

ALTER TABLE public.circle_feed_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_post_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Feed audiences read posts" ON public.circle_feed_posts FOR SELECT TO authenticated USING(public.circle_has_active_org_access(organization_id) AND (audience='organization' OR public.circle_can_access_group(cell_group_id)));
CREATE POLICY "Members create feed posts" ON public.circle_feed_posts FOR INSERT TO authenticated WITH CHECK(author_person_id=public.circle_current_person_id(organization_id) AND public.circle_has_active_org_access(organization_id) AND (audience='organization' OR public.circle_can_access_group(cell_group_id)));
CREATE POLICY "Authors update feed posts" ON public.circle_feed_posts FOR UPDATE TO authenticated USING(author_person_id=public.circle_current_person_id(organization_id)) WITH CHECK(author_person_id=public.circle_current_person_id(organization_id));
CREATE POLICY "Authors and moderators delete feed posts" ON public.circle_feed_posts FOR DELETE TO authenticated USING(author_person_id=public.circle_current_person_id(organization_id) OR public.circle_is_org_admin(organization_id) OR (cell_group_id IS NOT NULL AND public.circle_can_lead_group(cell_group_id)));
CREATE POLICY "Feed audiences read items" ON public.circle_feed_items FOR SELECT TO authenticated USING(public.circle_feed_item_visible(id));
CREATE POLICY "Feed audiences read photos" ON public.circle_feed_post_photos FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.circle_feed_posts post JOIN public.circle_feed_items item ON item.source_type='post' AND item.source_id=post.id WHERE post.id=circle_feed_post_photos.post_id AND public.circle_feed_item_visible(item.id)));
CREATE POLICY "Post authors add photos" ON public.circle_feed_post_photos FOR INSERT TO authenticated WITH CHECK(EXISTS(SELECT 1 FROM public.circle_feed_posts post WHERE post.id=circle_feed_post_photos.post_id AND post.organization_id=circle_feed_post_photos.organization_id AND post.author_person_id=public.circle_current_person_id(post.organization_id)));
CREATE POLICY "Post authors delete photos" ON public.circle_feed_post_photos FOR DELETE TO authenticated USING(EXISTS(SELECT 1 FROM public.circle_feed_posts post WHERE post.id=circle_feed_post_photos.post_id AND post.author_person_id=public.circle_current_person_id(post.organization_id)));
CREATE POLICY "Feed audiences read comments" ON public.circle_feed_comments FOR SELECT TO authenticated USING(public.circle_feed_item_visible(feed_item_id));
CREATE POLICY "Feed audiences create comments" ON public.circle_feed_comments FOR INSERT TO authenticated WITH CHECK(public.circle_feed_item_visible(feed_item_id) AND EXISTS(SELECT 1 FROM public.circle_feed_items item WHERE item.id=feed_item_id AND circle_feed_comments.author_person_id=public.circle_current_person_id(item.organization_id)));
CREATE POLICY "Comment authors update comments" ON public.circle_feed_comments FOR UPDATE TO authenticated USING(EXISTS(SELECT 1 FROM public.circle_feed_items item WHERE item.id=feed_item_id AND circle_feed_comments.author_person_id=public.circle_current_person_id(item.organization_id))) WITH CHECK(EXISTS(SELECT 1 FROM public.circle_feed_items item WHERE item.id=feed_item_id AND circle_feed_comments.author_person_id=public.circle_current_person_id(item.organization_id)));
CREATE POLICY "Authors and moderators delete comments" ON public.circle_feed_comments FOR DELETE TO authenticated USING(EXISTS(SELECT 1 FROM public.circle_feed_items item WHERE item.id=feed_item_id AND (circle_feed_comments.author_person_id=public.circle_current_person_id(item.organization_id) OR public.circle_feed_item_moderatable(item.id))));
CREATE POLICY "Feed audiences read likes" ON public.circle_feed_likes FOR SELECT TO authenticated USING(public.circle_feed_item_visible(feed_item_id));
CREATE POLICY "Members add own likes" ON public.circle_feed_likes FOR INSERT TO authenticated WITH CHECK(public.circle_feed_item_visible(feed_item_id) AND EXISTS(SELECT 1 FROM public.circle_feed_items item WHERE item.id=feed_item_id AND circle_feed_likes.person_id=public.circle_current_person_id(item.organization_id)));
CREATE POLICY "Members remove own likes" ON public.circle_feed_likes FOR DELETE TO authenticated USING(EXISTS(SELECT 1 FROM public.circle_feed_items item WHERE item.id=feed_item_id AND circle_feed_likes.person_id=public.circle_current_person_id(item.organization_id)));
CREATE POLICY "Members read own feed notifications" ON public.circle_feed_notifications FOR SELECT TO authenticated USING(recipient_person_id=public.circle_current_person_id(organization_id));
CREATE POLICY "Members update own feed notifications" ON public.circle_feed_notifications FOR UPDATE TO authenticated USING(recipient_person_id=public.circle_current_person_id(organization_id)) WITH CHECK(recipient_person_id=public.circle_current_person_id(organization_id));

DROP POLICY IF EXISTS "Gathering audiences read completed reflections" ON public.circle_gathering_reflections;
DROP POLICY IF EXISTS "Members create own completed gathering reflections" ON public.circle_gathering_reflections;
CREATE POLICY "Reflection audiences read completed reflections" ON public.circle_gathering_reflections FOR SELECT TO authenticated USING(public.circle_has_active_org_access(organization_id) AND (scope='organization' OR public.circle_can_access_group(cell_group_id)));
CREATE POLICY "Members create scoped gathering reflections" ON public.circle_gathering_reflections FOR INSERT TO authenticated WITH CHECK(author_person_id=public.circle_current_person_id(organization_id) AND public.circle_can_access_gathering(gathering_id) AND (scope='organization' OR public.circle_can_access_group(cell_group_id)) AND EXISTS(SELECT 1 FROM public.circle_gatherings gathering WHERE gathering.id=gathering_id AND gathering.status='completed'));

CREATE OR REPLACE FUNCTION public.set_circle_feed_item_hidden(p_feed_item_id UUID,p_hidden BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT public.circle_feed_item_moderatable(p_feed_item_id) THEN RAISE EXCEPTION 'Feed moderation access required'; END IF;
  UPDATE public.circle_feed_items SET hidden_at=CASE WHEN p_hidden THEN now() ELSE NULL END,hidden_by=CASE WHEN p_hidden THEN auth.uid() ELSE NULL END WHERE id=p_feed_item_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_community_feed(p_before_created_at TIMESTAMPTZ DEFAULT NULL,p_before_id UUID DEFAULT NULL,p_limit INTEGER DEFAULT 20,p_circle_id UUID DEFAULT NULL,p_organization_only BOOLEAN DEFAULT false)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE page JSONB; next_created_at TIMESTAMPTZ; next_id UUID; bounded_limit INTEGER:=least(greatest(coalesce(p_limit,20),1),50);
BEGIN
  WITH visible AS (
    SELECT item.* FROM public.circle_feed_items item
    WHERE public.circle_feed_item_visible(item.id)
      AND (p_circle_id IS NULL OR item.cell_group_id=p_circle_id)
      AND (NOT p_organization_only OR item.audience='organization')
      AND (p_before_created_at IS NULL OR (item.created_at,item.id)<(p_before_created_at,p_before_id))
      AND NOT EXISTS(SELECT 1 FROM public.circle_gatherings expired_gathering WHERE item.source_type='gathering' AND expired_gathering.id=item.source_id AND expired_gathering.starts_at<now())
      AND NOT EXISTS(SELECT 1 FROM public.circle_announcements expired_announcement WHERE item.source_type='announcement' AND expired_announcement.id=item.source_id AND expired_announcement.expires_at IS NOT NULL AND expired_announcement.expires_at<=now())
    ORDER BY item.created_at DESC,item.id DESC LIMIT bounded_limit+1
  ), selected AS (SELECT * FROM visible ORDER BY created_at DESC,id DESC LIMIT bounded_limit)
  SELECT jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object(
    'id',item.id,'type',item.source_type,'sourceId',item.source_id,'audience',item.audience,'groupId',item.cell_group_id,
    'destinationName',coalesce(group_row.name,'Entire organization'),'authorPersonId',item.author_person_id,
    'authorName',coalesce(nullif(concat_ws(' ',person.first_name,person.last_name),''),'Community leader'),'authorAvatarUrl',author_profile.avatar_url,
    'title',CASE item.source_type WHEN 'prayer' THEN prayer.title WHEN 'gathering' THEN gathering.title WHEN 'announcement' THEN announcement.title END,
    'body',CASE item.source_type WHEN 'post' THEN post.body WHEN 'reflection' THEN reflection.body WHEN 'prayer' THEN prayer.description WHEN 'announcement' THEN announcement.body END,
    'createdAt',item.created_at,'updatedAt',coalesce(post.updated_at,reflection.updated_at,prayer.updated_at,announcement.updated_at,gathering.updated_at),
    'gatheringId',CASE WHEN reflection.id IS NULL OR public.circle_can_access_gathering(reflection.gathering_id) THEN coalesce(reflection.gathering_id,gathering.id) END,'gatheringTitle',coalesce(reflection_gathering.title,gathering.title),'gatheringDate',coalesce(reflection_gathering.starts_at,gathering.starts_at),
    'prayer',CASE WHEN prayer.id IS NULL THEN NULL ELSE jsonb_build_object('id',prayer.id,'groupId',prayer.cell_group_id,'scope',prayer.scope,'userId',prayer.person_id,'authorName',concat_ws(' ',person.first_name,person.last_name),'title',prayer.title,'description',prayer.description,'category',prayer.category,'isAnswered',prayer.is_answered,'answeredNotes',prayer.answered_notes,'createdAt',prayer.created_at,'prayerCount',(SELECT count(*) FROM public.circle_prayer_clicks click WHERE click.prayer_id=prayer.id),'prayedByMe',EXISTS(SELECT 1 FROM public.circle_prayer_clicks click WHERE click.prayer_id=prayer.id AND click.person_id=public.circle_current_person_id(item.organization_id)),'destinationName',coalesce(group_row.name,'Entire organization')) END,
    'meeting',CASE WHEN gathering.id IS NULL THEN NULL ELSE jsonb_build_object('id',gathering.id,'organizationId',gathering.organization_id,'groupId',gathering.cell_group_id,'scope',gathering.scope,'destinationName',coalesce(group_row.name,'Everyone'),'title',gathering.title,'meetingDate',gathering.starts_at,'endsAt',gathering.ends_at,'location',gathering.location,'studyTopic',gathering.study_topic,'notes',gathering.notes,'status',gathering.status,'createdBy',gathering.created_by,'rsvps',coalesce((SELECT jsonb_object_agg(rsvp.person_id,rsvp.status) FROM public.circle_gathering_rsvps rsvp WHERE rsvp.gathering_id=gathering.id AND rsvp.person_id=public.circle_current_person_id(item.organization_id)),'{}'::jsonb)) END,
    'photos',coalesce((SELECT jsonb_agg(jsonb_build_object('id',photo.id,'url',photo.storage_path,'altText',photo.alt_text,'displayOrder',photo.display_order) ORDER BY photo.display_order) FROM public.circle_feed_post_photos photo WHERE photo.post_id=post.id),'[]'::jsonb),
    'comments',coalesce((SELECT jsonb_agg(comment_json ORDER BY comment_json->>'createdAt') FROM (SELECT jsonb_build_object('id',comment.id,'authorPersonId',comment.author_person_id,'authorName',concat_ws(' ',comment_person.first_name,comment_person.last_name),'authorAvatarUrl',comment_profile.avatar_url,'body',comment.body,'createdAt',comment.created_at,'updatedAt',comment.updated_at,'canEdit',comment.author_person_id=public.circle_current_person_id(item.organization_id),'canModerate',public.circle_feed_item_moderatable(item.id)) comment_json FROM public.circle_feed_comments comment JOIN public.people comment_person ON comment_person.id=comment.author_person_id LEFT JOIN public.circle_user_links comment_link ON comment_link.organization_id=item.organization_id AND comment_link.person_id=comment.author_person_id AND comment_link.status='active' LEFT JOIN public.profiles comment_profile ON comment_profile.id=comment_link.user_id WHERE comment.feed_item_id=item.id ORDER BY comment.created_at DESC LIMIT 2) preview),'[]'::jsonb),
    'commentCount',(SELECT count(*) FROM public.circle_feed_comments comment WHERE comment.feed_item_id=item.id),
    'likeCount',(SELECT count(*) FROM public.circle_feed_likes liked WHERE liked.feed_item_id=item.id),
    'likedByMe',EXISTS(SELECT 1 FROM public.circle_feed_likes liked WHERE liked.feed_item_id=item.id AND liked.person_id=public.circle_current_person_id(item.organization_id)),
    'canEdit',item.author_person_id=public.circle_current_person_id(item.organization_id),'canModerate',public.circle_feed_item_moderatable(item.id),'isHidden',false
  ) ORDER BY item.created_at DESC,item.id DESC),'[]'::jsonb)) INTO page
  FROM selected item
  LEFT JOIN public.people person ON person.id=item.author_person_id
  LEFT JOIN public.circle_user_links author_link ON author_link.organization_id=item.organization_id AND author_link.person_id=item.author_person_id AND author_link.status='active'
  LEFT JOIN public.profiles author_profile ON author_profile.id=author_link.user_id
  LEFT JOIN public.cell_groups group_row ON group_row.id=item.cell_group_id
  LEFT JOIN public.circle_feed_posts post ON item.source_type='post' AND post.id=item.source_id
  LEFT JOIN public.circle_gathering_reflections reflection ON item.source_type='reflection' AND reflection.id=item.source_id
  LEFT JOIN public.circle_gatherings reflection_gathering ON reflection_gathering.id=reflection.gathering_id
  LEFT JOIN public.circle_prayer_requests prayer ON item.source_type='prayer' AND prayer.id=item.source_id
  LEFT JOIN public.circle_gatherings gathering ON item.source_type='gathering' AND gathering.id=item.source_id
  LEFT JOIN public.circle_announcements announcement ON item.source_type='announcement' AND announcement.id=item.source_id;
  SELECT item.created_at,item.id INTO next_created_at,next_id
  FROM public.circle_feed_items item
  WHERE public.circle_feed_item_visible(item.id)
    AND (p_circle_id IS NULL OR item.cell_group_id=p_circle_id)
    AND (NOT p_organization_only OR item.audience='organization')
    AND (p_before_created_at IS NULL OR (item.created_at,item.id)<(p_before_created_at,p_before_id))
    AND NOT EXISTS(SELECT 1 FROM public.circle_gatherings expired_gathering WHERE item.source_type='gathering' AND expired_gathering.id=item.source_id AND expired_gathering.starts_at<now())
    AND NOT EXISTS(SELECT 1 FROM public.circle_announcements expired_announcement WHERE item.source_type='announcement' AND expired_announcement.id=item.source_id AND expired_announcement.expires_at IS NOT NULL AND expired_announcement.expires_at<=now())
  ORDER BY item.created_at DESC,item.id DESC OFFSET bounded_limit LIMIT 1;
  IF next_id IS NOT NULL THEN
    SELECT item.created_at,item.id INTO next_created_at,next_id
    FROM public.circle_feed_items item
    WHERE public.circle_feed_item_visible(item.id)
      AND (p_circle_id IS NULL OR item.cell_group_id=p_circle_id)
      AND (NOT p_organization_only OR item.audience='organization')
      AND (p_before_created_at IS NULL OR (item.created_at,item.id)<(p_before_created_at,p_before_id))
      AND NOT EXISTS(SELECT 1 FROM public.circle_gatherings expired_gathering WHERE item.source_type='gathering' AND expired_gathering.id=item.source_id AND expired_gathering.starts_at<now())
      AND NOT EXISTS(SELECT 1 FROM public.circle_announcements expired_announcement WHERE item.source_type='announcement' AND expired_announcement.id=item.source_id AND expired_announcement.expires_at IS NOT NULL AND expired_announcement.expires_at<=now())
    ORDER BY item.created_at DESC,item.id DESC OFFSET bounded_limit-1 LIMIT 1;
  END IF;
  RETURN coalesce(page,'{"items":[]}'::jsonb) || jsonb_build_object('nextCursor',CASE WHEN next_id IS NULL THEN NULL ELSE jsonb_build_object('createdAt',next_created_at,'id',next_id) END);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_feed_comments(p_feed_item_id UUID,p_after_created_at TIMESTAMPTZ DEFAULT NULL,p_after_id UUID DEFAULT NULL,p_limit INTEGER DEFAULT 50)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result JSONB; bounded_limit INTEGER:=least(greatest(coalesce(p_limit,50),1),200);
BEGIN
  WITH visible AS (
    SELECT comment.created_at,comment.id,jsonb_build_object('id',comment.id,'authorPersonId',comment.author_person_id,'authorName',concat_ws(' ',person.first_name,person.last_name),'authorAvatarUrl',profile.avatar_url,'body',comment.body,'createdAt',comment.created_at,'updatedAt',comment.updated_at,'canEdit',comment.author_person_id=public.circle_current_person_id(item.organization_id),'canModerate',public.circle_feed_item_moderatable(item.id)) AS payload
    FROM public.circle_feed_comments comment JOIN public.circle_feed_items item ON item.id=comment.feed_item_id JOIN public.people person ON person.id=comment.author_person_id LEFT JOIN public.circle_user_links link ON link.organization_id=item.organization_id AND link.person_id=comment.author_person_id AND link.status='active' LEFT JOIN public.profiles profile ON profile.id=link.user_id
    WHERE comment.feed_item_id=p_feed_item_id AND public.circle_feed_item_visible(item.id)
      AND (p_after_created_at IS NULL OR (comment.created_at,comment.id)>(p_after_created_at,p_after_id))
    ORDER BY comment.created_at,comment.id LIMIT bounded_limit+1
  ), selected AS (SELECT * FROM visible ORDER BY created_at,id LIMIT bounded_limit)
  SELECT jsonb_build_object(
    'comments',coalesce(jsonb_agg(payload ORDER BY created_at,id),'[]'::jsonb),
    'nextCursor',CASE WHEN (SELECT count(*) FROM visible)>bounded_limit THEN (SELECT jsonb_build_object('createdAt',created_at,'id',id) FROM visible ORDER BY created_at,id OFFSET bounded_limit-1 LIMIT 1) END
  ) INTO result FROM selected;
  RETURN coalesce(result,'{"comments":[],"nextCursor":null}'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_feed_notifications(p_before_updated_at TIMESTAMPTZ DEFAULT NULL,p_before_id UUID DEFAULT NULL,p_limit INTEGER DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result JSONB; bounded_limit INTEGER:=least(greatest(coalesce(p_limit,30),1),100);
BEGIN
  WITH visible AS (
    SELECT notice.updated_at,notice.id,jsonb_build_object('id',notice.id,'feedItemId',notice.feed_item_id,'kind',notice.kind,'actorCount',notice.actor_count,'actorName',concat_ws(' ',person.first_name,person.last_name),'readAt',notice.read_at,'createdAt',notice.updated_at) payload
    FROM public.circle_feed_notifications notice JOIN public.people person ON person.id=notice.latest_actor_person_id
    WHERE notice.recipient_person_id=public.circle_current_person_id(notice.organization_id)
      AND (p_before_updated_at IS NULL OR (notice.updated_at,notice.id)<(p_before_updated_at,p_before_id))
    ORDER BY notice.updated_at DESC,notice.id DESC LIMIT bounded_limit+1
  ), selected AS (SELECT * FROM visible ORDER BY updated_at DESC,id DESC LIMIT bounded_limit)
  SELECT jsonb_build_object(
    'notifications',coalesce(jsonb_agg(payload ORDER BY updated_at DESC,id DESC),'[]'::jsonb),
    'nextCursor',CASE WHEN (SELECT count(*) FROM visible)>bounded_limit THEN (SELECT jsonb_build_object('createdAt',updated_at,'id',id) FROM visible ORDER BY updated_at DESC,id DESC OFFSET bounded_limit-1 LIMIT 1) END
  ) INTO result FROM selected;
  RETURN coalesce(result,'{"notifications":[],"nextCursor":null}'::jsonb);
END;
$$;
CREATE OR REPLACE FUNCTION public.mark_circle_feed_notifications_read()
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ UPDATE public.circle_feed_notifications notice SET read_at=now() WHERE notice.recipient_person_id=public.circle_current_person_id(notice.organization_id) AND notice.read_at IS NULL $$;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('circle-feed-media','circle-feed-media',false,10485760,ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
CREATE POLICY "Feed audiences read private media" ON storage.objects FOR SELECT TO authenticated USING(bucket_id='circle-feed-media' AND EXISTS(SELECT 1 FROM public.circle_feed_post_photos photo JOIN public.circle_feed_posts post ON post.id=photo.post_id JOIN public.circle_feed_items item ON item.source_type='post' AND item.source_id=post.id WHERE photo.storage_path=name AND public.circle_feed_item_visible(item.id)));
CREATE POLICY "Members upload own feed media" ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='circle-feed-media' AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' AND (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' AND (storage.foldername(name))[2]::uuid=public.circle_current_person_id((storage.foldername(name))[1]::uuid));
CREATE POLICY "Members delete own feed media" ON storage.objects FOR DELETE TO authenticated USING(bucket_id='circle-feed-media' AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' AND (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' AND ((storage.foldername(name))[2]::uuid=public.circle_current_person_id((storage.foldername(name))[1]::uuid) OR public.circle_is_org_admin((storage.foldername(name))[1]::uuid)));

GRANT SELECT,INSERT,UPDATE,DELETE ON public.circle_feed_posts,public.circle_feed_post_photos,public.circle_feed_comments,public.circle_feed_likes TO authenticated;
GRANT SELECT,UPDATE ON public.circle_feed_notifications TO authenticated;
GRANT SELECT ON public.circle_feed_items TO authenticated;
REVOKE ALL ON FUNCTION public.circle_sync_feed_post(),public.circle_sync_feed_reflection(),public.circle_sync_feed_prayer(),public.circle_sync_feed_gathering(),public.circle_sync_feed_announcement(),public.circle_notify_feed_activity(),public.circle_limit_feed_photos(),public.circle_validate_feed_post(),public.circle_validate_reflection_feed_scope(),public.circle_prepare_feed_comment() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_circle_community_feed(TIMESTAMPTZ,UUID,INTEGER,UUID,BOOLEAN),public.get_circle_feed_comments(UUID,TIMESTAMPTZ,UUID,INTEGER),public.get_circle_feed_notifications(TIMESTAMPTZ,UUID,INTEGER),public.mark_circle_feed_notifications_read(),public.set_circle_feed_item_hidden(UUID,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_circle_community_feed(TIMESTAMPTZ,UUID,INTEGER,UUID,BOOLEAN),public.get_circle_feed_comments(UUID,TIMESTAMPTZ,UUID,INTEGER),public.get_circle_feed_notifications(TIMESTAMPTZ,UUID,INTEGER),public.mark_circle_feed_notifications_read(),public.set_circle_feed_item_hidden(UUID,BOOLEAN) TO authenticated;

-- Preserve historical visibility while making current content discoverable.
INSERT INTO public.circle_feed_items(organization_id,cell_group_id,origin_cell_group_id,audience,source_type,source_id,author_person_id,created_at)
SELECT reflection.organization_id,reflection.cell_group_id,gathering.cell_group_id,reflection.scope,'reflection',reflection.id,reflection.author_person_id,reflection.created_at FROM public.circle_gathering_reflections reflection JOIN public.circle_gatherings gathering ON gathering.id=reflection.gathering_id ON CONFLICT DO NOTHING;
INSERT INTO public.circle_feed_items(organization_id,cell_group_id,origin_cell_group_id,audience,source_type,source_id,author_person_id,created_at)
SELECT organization_id,cell_group_id,cell_group_id,scope,'prayer',id,person_id,created_at FROM public.circle_prayer_requests WHERE NOT is_answered ON CONFLICT DO NOTHING;
INSERT INTO public.circle_feed_items(organization_id,cell_group_id,origin_cell_group_id,audience,source_type,source_id,author_person_id,created_at)
SELECT announcement.organization_id,announcement.cell_group_id,announcement.cell_group_id,CASE WHEN announcement.cell_group_id IS NULL THEN 'organization' ELSE 'circle' END,'announcement',announcement.id,link.person_id,announcement.published_at FROM public.circle_announcements announcement LEFT JOIN public.circle_user_links link ON link.organization_id=announcement.organization_id AND link.user_id=announcement.created_by AND link.status='active' WHERE announcement.assignment_confirmed_at IS NOT NULL AND (announcement.expires_at IS NULL OR announcement.expires_at>now()) ON CONFLICT DO NOTHING;
INSERT INTO public.circle_feed_items(organization_id,cell_group_id,origin_cell_group_id,audience,source_type,source_id,author_person_id,created_at)
SELECT gathering.organization_id,gathering.cell_group_id,gathering.cell_group_id,CASE WHEN gathering.scope='organization' THEN 'organization' ELSE 'circle' END,'gathering',gathering.id,link.person_id,gathering.created_at FROM public.circle_gatherings gathering LEFT JOIN public.circle_user_links link ON link.organization_id=gathering.organization_id AND link.user_id=gathering.created_by AND link.status='active' WHERE gathering.status='scheduled' AND gathering.starts_at>=now() AND gathering.assignment_confirmed_at IS NOT NULL ON CONFLICT DO NOTHING;

COMMIT;
