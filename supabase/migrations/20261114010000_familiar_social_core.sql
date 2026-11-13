BEGIN;

ALTER TABLE public.circle_feed_items
  ADD COLUMN activity_at TIMESTAMPTZ,
  ADD COLUMN comments_enabled BOOLEAN NOT NULL DEFAULT true;
UPDATE public.circle_feed_items SET activity_at=created_at WHERE activity_at IS NULL;
ALTER TABLE public.circle_feed_items ALTER COLUMN activity_at SET NOT NULL;
ALTER TABLE public.circle_feed_items ALTER COLUMN activity_at SET DEFAULT now();
CREATE INDEX circle_feed_items_activity_page_idx ON public.circle_feed_items(organization_id,activity_at DESC,id DESC) WHERE hidden_at IS NULL;
CREATE INDEX circle_feed_items_circle_activity_page_idx ON public.circle_feed_items(cell_group_id,activity_at DESC,id DESC) WHERE hidden_at IS NULL;

CREATE TABLE public.circle_community_profiles (
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  bio TEXT NOT NULL DEFAULT '' CHECK (char_length(bio)<=500),
  bio_visibility TEXT NOT NULL DEFAULT 'organization' CHECK (bio_visibility IN ('organization','shared_circle','hidden')),
  join_date_visibility TEXT NOT NULL DEFAULT 'hidden' CHECK (join_date_visibility IN ('organization','shared_circle','hidden')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(organization_id,person_id)
);

CREATE TABLE public.circle_feed_reactions (
  feed_item_id UUID NOT NULL REFERENCES public.circle_feed_items(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  reaction_type TEXT NOT NULL CHECK (reaction_type IN ('like','amen','celebrate','support')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(feed_item_id,person_id)
);
CREATE INDEX circle_feed_reactions_item_idx ON public.circle_feed_reactions(feed_item_id,reaction_type);

CREATE TABLE public.circle_feed_saves (
  feed_item_id UUID NOT NULL REFERENCES public.circle_feed_items(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(feed_item_id,person_id)
);

CREATE TABLE public.circle_feed_hidden_items (
  feed_item_id UUID NOT NULL REFERENCES public.circle_feed_items(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(feed_item_id,person_id)
);

CREATE TABLE public.circle_feed_subscriptions (
  feed_item_id UUID NOT NULL REFERENCES public.circle_feed_items(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(feed_item_id,person_id)
);

CREATE TABLE public.circle_feed_read_state (
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(organization_id,person_id)
);

CREATE TABLE public.circle_feed_pins (
  feed_item_id UUID PRIMARY KEY REFERENCES public.circle_feed_items(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE CASCADE,
  pinned_by_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX circle_feed_pins_scope_idx ON public.circle_feed_pins(organization_id,cell_group_id,created_at DESC);

CREATE TABLE public.circle_feed_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  feed_item_id UUID NOT NULL REFERENCES public.circle_feed_items(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  reporter_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  reason TEXT NOT NULL CHECK (reason IN ('spam','harassment','privacy','inappropriate','other')),
  note TEXT CHECK (note IS NULL OR char_length(note)<=1000),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','dismissed')),
  resolved_by_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(feed_item_id,reporter_person_id)
);
CREATE INDEX circle_feed_reports_queue_idx ON public.circle_feed_reports(organization_id,status,created_at DESC);

CREATE TABLE public.circle_feed_report_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NOT NULL REFERENCES public.circle_feed_reports(id) ON DELETE CASCADE,
  actor_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('reported','resolved','dismissed','reopened')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.circle_prayer_updates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prayer_id UUID NOT NULL REFERENCES public.circle_prayer_requests(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  author_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  update_type TEXT NOT NULL CHECK (update_type IN ('progress','praise','answered','reopened')),
  body TEXT NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 2000),
  hidden_at TIMESTAMPTZ,
  hidden_by_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX circle_prayer_updates_timeline_idx ON public.circle_prayer_updates(prayer_id,created_at,id) WHERE hidden_at IS NULL;

ALTER TABLE public.circle_feed_notifications
  DROP CONSTRAINT circle_feed_notifications_kind_check,
  ADD COLUMN target_comment_id UUID REFERENCES public.circle_feed_comments(id) ON DELETE SET NULL,
  ADD COLUMN prayer_update_id UUID REFERENCES public.circle_prayer_updates(id) ON DELETE SET NULL,
  ADD CONSTRAINT circle_feed_notifications_kind_check CHECK (kind IN ('comment','like','pray','reaction','prayer_update','report_resolved'));

ALTER TABLE public.circle_community_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_saves ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_hidden_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_read_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_pins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_feed_report_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_prayer_updates ENABLE ROW LEVEL SECURITY;

INSERT INTO public.circle_feed_reactions(feed_item_id,person_id,reaction_type,created_at,updated_at)
SELECT feed_item_id,person_id,'like',created_at,created_at FROM public.circle_feed_likes
ON CONFLICT(feed_item_id,person_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.circle_sync_legacy_like_to_reaction()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    DELETE FROM public.circle_feed_reactions WHERE feed_item_id=OLD.feed_item_id AND person_id=OLD.person_id AND reaction_type='like';
    RETURN OLD;
  END IF;
  INSERT INTO public.circle_feed_reactions(feed_item_id,person_id,reaction_type,created_at,updated_at)
  VALUES(NEW.feed_item_id,NEW.person_id,'like',NEW.created_at,now())
  ON CONFLICT(feed_item_id,person_id) DO UPDATE SET reaction_type='like',updated_at=now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_feed_likes_sync_reactions AFTER INSERT OR DELETE ON public.circle_feed_likes
FOR EACH ROW EXECUTE FUNCTION public.circle_sync_legacy_like_to_reaction();

CREATE OR REPLACE FUNCTION public.circle_sync_reaction_to_legacy_like()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF TG_OP='DELETE' OR NEW.reaction_type<>'like' THEN
    DELETE FROM public.circle_feed_likes WHERE feed_item_id=coalesce(NEW.feed_item_id,OLD.feed_item_id) AND person_id=coalesce(NEW.person_id,OLD.person_id);
  ELSE
    INSERT INTO public.circle_feed_likes(feed_item_id,person_id,created_at)
    VALUES(NEW.feed_item_id,NEW.person_id,NEW.created_at) ON CONFLICT(feed_item_id,person_id) DO NOTHING;
  END IF;
  RETURN coalesce(NEW,OLD);
END;
$$;
CREATE TRIGGER circle_feed_reactions_sync_likes AFTER INSERT OR UPDATE OR DELETE ON public.circle_feed_reactions
FOR EACH ROW EXECUTE FUNCTION public.circle_sync_reaction_to_legacy_like();

CREATE OR REPLACE FUNCTION public.circle_feed_item_personally_visible(p_feed_item_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT public.circle_feed_item_visible(p_feed_item_id)
    AND NOT EXISTS(
      SELECT 1 FROM public.circle_feed_hidden_items hidden
      JOIN public.circle_feed_items item ON item.id=hidden.feed_item_id
      WHERE hidden.feed_item_id=p_feed_item_id
        AND hidden.person_id=public.circle_current_person_id(item.organization_id)
    );
$$;

CREATE OR REPLACE FUNCTION public.circle_can_view_profile_field(
  p_organization_id UUID,p_target_person_id UUID,p_visibility TEXT
)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT public.circle_has_active_org_access(p_organization_id) AND (
    p_target_person_id=public.circle_current_person_id(p_organization_id)
    OR public.circle_is_org_admin(p_organization_id)
    OR p_visibility='organization'
    OR (p_visibility='shared_circle' AND EXISTS(
      SELECT 1 FROM public.cell_group_members target_member
      JOIN public.cell_group_members viewer_member ON viewer_member.cell_group_id=target_member.cell_group_id
      WHERE target_member.person_id=p_target_person_id
        AND viewer_member.person_id=public.circle_current_person_id(p_organization_id)
    ))
  );
$$;

CREATE OR REPLACE FUNCTION public.circle_feed_item_json_v2(p_feed_item_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result JSONB;
BEGIN
  IF NOT public.circle_feed_item_personally_visible(p_feed_item_id) THEN RETURN NULL; END IF;
  SELECT jsonb_build_object(
    'id',item.id,'type',item.source_type,'sourceId',item.source_id,'audience',item.audience,'groupId',item.cell_group_id,
    'destinationName',coalesce(group_row.name,'Entire organization'),'authorPersonId',item.author_person_id,
    'authorName',coalesce(nullif(concat_ws(' ',person.first_name,person.last_name),''),'Community leader'),'authorAvatarUrl',author_profile.avatar_url,
    'title',CASE item.source_type WHEN 'prayer' THEN prayer.title WHEN 'gathering' THEN gathering.title WHEN 'announcement' THEN announcement.title END,
    'body',CASE item.source_type WHEN 'post' THEN post.body WHEN 'reflection' THEN reflection.body WHEN 'prayer' THEN prayer.description WHEN 'announcement' THEN announcement.body END,
    'createdAt',item.created_at,'activityAt',item.activity_at,'updatedAt',coalesce(post.updated_at,reflection.updated_at,prayer.updated_at,announcement.updated_at,gathering.updated_at),
    'gatheringId',CASE WHEN reflection.id IS NULL OR public.circle_can_access_gathering(reflection.gathering_id) THEN coalesce(reflection.gathering_id,gathering.id) END,
    'gatheringTitle',coalesce(reflection_gathering.title,gathering.title),'gatheringDate',coalesce(reflection_gathering.starts_at,gathering.starts_at),
    'prayer',CASE WHEN prayer.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',prayer.id,'groupId',prayer.cell_group_id,'scope',prayer.scope,'userId',prayer.person_id,
      'authorName',concat_ws(' ',person.first_name,person.last_name),'title',prayer.title,'description',prayer.description,
      'category',prayer.category,'isAnswered',prayer.is_answered,'answeredNotes',prayer.answered_notes,'createdAt',prayer.created_at,
      'prayerCount',(SELECT count(*) FROM public.circle_prayer_clicks click WHERE click.prayer_id=prayer.id),
      'prayedByMe',EXISTS(SELECT 1 FROM public.circle_prayer_clicks click WHERE click.prayer_id=prayer.id AND click.person_id=public.circle_current_person_id(item.organization_id)),
      'destinationName',coalesce(group_row.name,'Entire organization')) END,
    'meeting',CASE WHEN gathering.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',gathering.id,'organizationId',gathering.organization_id,'groupId',gathering.cell_group_id,'scope',gathering.scope,
      'destinationName',coalesce(group_row.name,'Everyone'),'title',gathering.title,'meetingDate',gathering.starts_at,'endsAt',gathering.ends_at,
      'location',gathering.location,'studyTopic',gathering.study_topic,'notes',gathering.notes,'status',gathering.status,'createdBy',gathering.created_by,
      'rsvps',coalesce((SELECT jsonb_object_agg(rsvp.person_id,rsvp.status) FROM public.circle_gathering_rsvps rsvp WHERE rsvp.gathering_id=gathering.id AND rsvp.person_id=public.circle_current_person_id(item.organization_id)),'{}'::jsonb)) END,
    'photos',coalesce((SELECT jsonb_agg(jsonb_build_object('id',photo.id,'url',photo.storage_path,'altText',photo.alt_text,'displayOrder',photo.display_order) ORDER BY photo.display_order) FROM public.circle_feed_post_photos photo WHERE photo.post_id=post.id),'[]'::jsonb),
    'comments',coalesce((SELECT jsonb_agg(comment_json ORDER BY comment_json->>'createdAt') FROM (
      SELECT jsonb_build_object('id',comment.id,'authorPersonId',comment.author_person_id,'authorName',concat_ws(' ',comment_person.first_name,comment_person.last_name),'authorAvatarUrl',comment_profile.avatar_url,'body',comment.body,'createdAt',comment.created_at,'updatedAt',comment.updated_at,'canEdit',comment.author_person_id=public.circle_current_person_id(item.organization_id),'canModerate',public.circle_feed_item_moderatable(item.id)) comment_json
      FROM public.circle_feed_comments comment JOIN public.people comment_person ON comment_person.id=comment.author_person_id
      LEFT JOIN public.circle_user_links comment_link ON comment_link.organization_id=item.organization_id AND comment_link.person_id=comment.author_person_id AND comment_link.status='active'
      LEFT JOIN public.profiles comment_profile ON comment_profile.id=comment_link.user_id WHERE comment.feed_item_id=item.id
      ORDER BY comment.created_at DESC LIMIT 2) preview),'[]'::jsonb),
    'commentCount',(SELECT count(*) FROM public.circle_feed_comments comment WHERE comment.feed_item_id=item.id),
    'commentsEnabled',item.comments_enabled,
    'likeCount',(SELECT count(*) FROM public.circle_feed_reactions reaction WHERE reaction.feed_item_id=item.id),
    'likedByMe',EXISTS(SELECT 1 FROM public.circle_feed_reactions reaction WHERE reaction.feed_item_id=item.id AND reaction.person_id=public.circle_current_person_id(item.organization_id)),
    'reactionSummary',jsonb_build_object(
      'like',(SELECT count(*) FROM public.circle_feed_reactions reaction WHERE reaction.feed_item_id=item.id AND reaction.reaction_type='like'),
      'amen',(SELECT count(*) FROM public.circle_feed_reactions reaction WHERE reaction.feed_item_id=item.id AND reaction.reaction_type='amen'),
      'celebrate',(SELECT count(*) FROM public.circle_feed_reactions reaction WHERE reaction.feed_item_id=item.id AND reaction.reaction_type='celebrate'),
      'support',(SELECT count(*) FROM public.circle_feed_reactions reaction WHERE reaction.feed_item_id=item.id AND reaction.reaction_type='support')),
    'myReaction',(SELECT reaction.reaction_type FROM public.circle_feed_reactions reaction WHERE reaction.feed_item_id=item.id AND reaction.person_id=public.circle_current_person_id(item.organization_id)),
    'savedByMe',EXISTS(SELECT 1 FROM public.circle_feed_saves saved WHERE saved.feed_item_id=item.id AND saved.person_id=public.circle_current_person_id(item.organization_id)),
    'followedByMe',EXISTS(SELECT 1 FROM public.circle_feed_subscriptions subscription WHERE subscription.feed_item_id=item.id AND subscription.person_id=public.circle_current_person_id(item.organization_id)),
    'isPinned',EXISTS(SELECT 1 FROM public.circle_feed_pins pin WHERE pin.feed_item_id=item.id),
    'isNew',item.activity_at>coalesce((SELECT state.last_seen_at FROM public.circle_feed_read_state state WHERE state.organization_id=item.organization_id AND state.person_id=public.circle_current_person_id(item.organization_id)),'epoch'::timestamptz),
    'latestPrayerUpdate',(SELECT jsonb_build_object('id',update_row.id,'prayerId',update_row.prayer_id,'authorPersonId',update_row.author_person_id,'authorName',concat_ws(' ',update_person.first_name,update_person.last_name),'type',update_row.update_type,'body',update_row.body,'createdAt',update_row.created_at,'updatedAt',update_row.updated_at,'canEdit',update_row.author_person_id=public.circle_current_person_id(item.organization_id),'canModerate',public.circle_feed_item_moderatable(item.id))
      FROM public.circle_prayer_updates update_row JOIN public.people update_person ON update_person.id=update_row.author_person_id
      WHERE update_row.prayer_id=prayer.id AND update_row.hidden_at IS NULL ORDER BY update_row.created_at DESC,update_row.id DESC LIMIT 1),
    'canEdit',item.author_person_id=public.circle_current_person_id(item.organization_id),
    'canModerate',public.circle_feed_item_moderatable(item.id),'isHidden',false
  ) INTO result
  FROM public.circle_feed_items item
  LEFT JOIN public.people person ON person.id=item.author_person_id
  LEFT JOIN public.circle_user_links author_link ON author_link.organization_id=item.organization_id AND author_link.person_id=item.author_person_id AND author_link.status='active'
  LEFT JOIN public.profiles author_profile ON author_profile.id=author_link.user_id
  LEFT JOIN public.cell_groups group_row ON group_row.id=item.cell_group_id
  LEFT JOIN public.circle_feed_posts post ON item.source_type='post' AND post.id=item.source_id
  LEFT JOIN public.circle_gathering_reflections reflection ON item.source_type='reflection' AND reflection.id=item.source_id
  LEFT JOIN public.circle_gatherings reflection_gathering ON reflection_gathering.id=reflection.gathering_id
  LEFT JOIN public.circle_prayer_requests prayer ON item.source_type='prayer' AND prayer.id=item.source_id
  LEFT JOIN public.circle_gatherings gathering ON item.source_type='gathering' AND gathering.id=item.source_id
  LEFT JOIN public.circle_announcements announcement ON item.source_type='announcement' AND announcement.id=item.source_id
  WHERE item.id=p_feed_item_id;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_community_feed_v2(
  p_before_activity_at TIMESTAMPTZ DEFAULT NULL,p_before_id UUID DEFAULT NULL,p_snapshot_at TIMESTAMPTZ DEFAULT NULL,
  p_limit INTEGER DEFAULT 20,p_circle_id UUID DEFAULT NULL,p_organization_only BOOLEAN DEFAULT false
)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result JSONB; bounded_limit INTEGER:=least(greatest(coalesce(p_limit,20),1),50); snapshot_at TIMESTAMPTZ:=coalesce(p_snapshot_at,clock_timestamp());
BEGIN
  WITH visible AS (
    SELECT item.id,item.activity_at FROM public.circle_feed_items item
    WHERE public.circle_feed_item_personally_visible(item.id)
      AND item.activity_at<=snapshot_at
      AND (p_circle_id IS NULL OR item.cell_group_id=p_circle_id)
      AND (NOT p_organization_only OR item.audience='organization')
      AND (p_before_activity_at IS NULL OR (item.activity_at,item.id)<(p_before_activity_at,p_before_id))
      AND NOT EXISTS(SELECT 1 FROM public.circle_gatherings expired WHERE item.source_type='gathering' AND expired.id=item.source_id AND expired.starts_at<now())
      AND NOT EXISTS(SELECT 1 FROM public.circle_announcements expired WHERE item.source_type='announcement' AND expired.id=item.source_id AND expired.expires_at IS NOT NULL AND expired.expires_at<=now())
    ORDER BY item.activity_at DESC,item.id DESC LIMIT bounded_limit+1
  ), selected AS (SELECT * FROM visible ORDER BY activity_at DESC,id DESC LIMIT bounded_limit)
  SELECT jsonb_build_object(
    'items',coalesce(jsonb_agg(public.circle_feed_item_json_v2(selected.id) ORDER BY selected.activity_at DESC,selected.id DESC),'[]'::jsonb),
    'nextCursor',CASE WHEN (SELECT count(*) FROM visible)>bounded_limit THEN
      (SELECT jsonb_build_object('activityAt',activity_at,'id',id,'snapshotAt',snapshot_at) FROM selected ORDER BY activity_at,id LIMIT 1) END,
    'snapshotAt',snapshot_at,
    'pinnedItems',coalesce((SELECT jsonb_agg(public.circle_feed_item_json_v2(pin.feed_item_id) ORDER BY pin.created_at DESC)
      FROM public.circle_feed_pins pin JOIN public.circle_feed_items pinned ON pinned.id=pin.feed_item_id
      WHERE public.circle_feed_item_personally_visible(pinned.id) AND (p_circle_id IS NULL OR pinned.cell_group_id=p_circle_id)
        AND (NOT p_organization_only OR pinned.audience='organization')),'[]'::jsonb)
  ) INTO result FROM selected;
  RETURN coalesce(result,jsonb_build_object('items','[]'::jsonb,'pinnedItems','[]'::jsonb,'nextCursor',NULL,'snapshotAt',snapshot_at));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_community_feed_item(p_feed_item_id UUID)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT public.circle_feed_item_json_v2(p_feed_item_id);
$$;

CREATE OR REPLACE FUNCTION public.set_circle_feed_reaction(p_feed_item_id UUID,p_reaction TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE; viewer UUID;
BEGIN
  IF NOT public.circle_feed_item_visible(p_feed_item_id) THEN RAISE EXCEPTION 'Feed access required'; END IF;
  SELECT * INTO item FROM public.circle_feed_items WHERE id=p_feed_item_id;
  viewer:=public.circle_current_person_id(item.organization_id);
  IF p_reaction IS NULL THEN DELETE FROM public.circle_feed_reactions WHERE feed_item_id=item.id AND person_id=viewer; RETURN; END IF;
  IF p_reaction NOT IN ('like','amen','celebrate','support') THEN RAISE EXCEPTION 'Unsupported reaction'; END IF;
  INSERT INTO public.circle_feed_reactions(feed_item_id,person_id,reaction_type)
  VALUES(item.id,viewer,p_reaction) ON CONFLICT(feed_item_id,person_id) DO UPDATE SET reaction_type=excluded.reaction_type,updated_at=now();
END;
$$;

CREATE OR REPLACE FUNCTION public.set_circle_feed_saved(p_feed_item_id UUID,p_saved BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE; viewer UUID;
BEGIN
  IF NOT public.circle_feed_item_visible(p_feed_item_id) THEN RAISE EXCEPTION 'Feed access required'; END IF;
  SELECT * INTO item FROM public.circle_feed_items WHERE id=p_feed_item_id; viewer:=public.circle_current_person_id(item.organization_id);
  IF p_saved THEN INSERT INTO public.circle_feed_saves(feed_item_id,person_id) VALUES(item.id,viewer) ON CONFLICT DO NOTHING;
  ELSE DELETE FROM public.circle_feed_saves WHERE feed_item_id=item.id AND person_id=viewer; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_circle_feed_personally_hidden(p_feed_item_id UUID,p_hidden BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE; viewer UUID;
BEGIN
  IF NOT public.circle_feed_item_visible(p_feed_item_id) THEN RAISE EXCEPTION 'Feed access required'; END IF;
  SELECT * INTO item FROM public.circle_feed_items WHERE id=p_feed_item_id; viewer:=public.circle_current_person_id(item.organization_id);
  IF p_hidden THEN INSERT INTO public.circle_feed_hidden_items(feed_item_id,person_id) VALUES(item.id,viewer) ON CONFLICT DO NOTHING;
  ELSE DELETE FROM public.circle_feed_hidden_items WHERE feed_item_id=item.id AND person_id=viewer; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.report_circle_feed_item(p_feed_item_id UUID,p_reason TEXT,p_note TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE; viewer UUID; report_id UUID;
BEGIN
  IF NOT public.circle_feed_item_visible(p_feed_item_id) THEN RAISE EXCEPTION 'Feed access required'; END IF;
  IF p_reason NOT IN ('spam','harassment','privacy','inappropriate','other') OR char_length(coalesce(p_note,''))>1000 THEN RAISE EXCEPTION 'Invalid report'; END IF;
  SELECT * INTO item FROM public.circle_feed_items WHERE id=p_feed_item_id; viewer:=public.circle_current_person_id(item.organization_id);
  INSERT INTO public.circle_feed_reports(feed_item_id,organization_id,reporter_person_id,reason,note)
  VALUES(item.id,item.organization_id,viewer,p_reason,nullif(btrim(p_note),''))
  ON CONFLICT(feed_item_id,reporter_person_id) DO UPDATE SET reason=excluded.reason,note=excluded.note,status='open',resolved_by_person_id=NULL,resolved_at=NULL,updated_at=now()
  RETURNING id INTO report_id;
  INSERT INTO public.circle_feed_report_actions(report_id,actor_person_id,action) VALUES(report_id,viewer,'reported');
  RETURN report_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_circle_feed_comments_enabled(p_feed_item_id UUID,p_enabled BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE;
BEGIN
  SELECT * INTO item FROM public.circle_feed_items WHERE id=p_feed_item_id;
  IF item.id IS NULL OR (item.author_person_id<>public.circle_current_person_id(item.organization_id) AND NOT public.circle_feed_item_moderatable(item.id)) THEN RAISE EXCEPTION 'Comment settings access required'; END IF;
  UPDATE public.circle_feed_items SET comments_enabled=p_enabled WHERE id=item.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_circle_feed_pinned(p_feed_item_id UUID,p_pinned BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE; viewer UUID; active_pins INTEGER;
BEGIN
  SELECT * INTO item FROM public.circle_feed_items WHERE id=p_feed_item_id;
  IF item.id IS NULL OR NOT public.circle_feed_item_moderatable(item.id) THEN RAISE EXCEPTION 'Pin access required'; END IF;
  viewer:=public.circle_current_person_id(item.organization_id);
  IF NOT p_pinned THEN DELETE FROM public.circle_feed_pins WHERE feed_item_id=item.id; RETURN; END IF;
  SELECT count(*) INTO active_pins FROM public.circle_feed_pins pin WHERE pin.organization_id=item.organization_id AND pin.cell_group_id IS NOT DISTINCT FROM item.cell_group_id AND pin.feed_item_id<>item.id;
  IF active_pins>=3 THEN RAISE EXCEPTION 'Unpin an item before pinning another'; END IF;
  INSERT INTO public.circle_feed_pins(feed_item_id,organization_id,cell_group_id,pinned_by_person_id)
  VALUES(item.id,item.organization_id,item.cell_group_id,viewer) ON CONFLICT(feed_item_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_circle_prayer_follow(p_prayer_id UUID,p_followed BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE; viewer UUID;
BEGIN
  SELECT * INTO item FROM public.circle_feed_items WHERE source_type='prayer' AND source_id=p_prayer_id;
  IF item.id IS NULL OR NOT public.circle_feed_item_visible(item.id) THEN RAISE EXCEPTION 'Prayer access required'; END IF;
  viewer:=public.circle_current_person_id(item.organization_id);
  IF p_followed THEN INSERT INTO public.circle_feed_subscriptions(feed_item_id,person_id) VALUES(item.id,viewer) ON CONFLICT DO NOTHING;
  ELSE DELETE FROM public.circle_feed_subscriptions WHERE feed_item_id=item.id AND person_id=viewer; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_circle_prayer_update(p_prayer_id UUID,p_update_type TEXT,p_body TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE prayer public.circle_prayer_requests%ROWTYPE; update_id UUID;
BEGIN
  SELECT * INTO prayer FROM public.circle_prayer_requests WHERE id=p_prayer_id;
  IF prayer.id IS NULL OR prayer.person_id<>public.circle_current_person_id(prayer.organization_id) THEN RAISE EXCEPTION 'Prayer author access required'; END IF;
  IF p_update_type NOT IN ('progress','praise','answered','reopened') OR char_length(btrim(p_body)) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Invalid prayer update'; END IF;
  INSERT INTO public.circle_prayer_updates(prayer_id,organization_id,author_person_id,update_type,body)
  VALUES(prayer.id,prayer.organization_id,prayer.person_id,p_update_type,btrim(p_body)) RETURNING id INTO update_id;
  IF p_update_type IN ('answered','praise') THEN UPDATE public.circle_prayer_requests SET is_answered=true,answered_notes=btrim(p_body),updated_at=now() WHERE id=prayer.id;
  ELSIF p_update_type='reopened' THEN UPDATE public.circle_prayer_requests SET is_answered=false,answered_notes=NULL,updated_at=now() WHERE id=prayer.id; END IF;
  RETURN update_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_prayer_updates(p_prayer_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE; result JSONB;
BEGIN
  SELECT * INTO item FROM public.circle_feed_items WHERE source_type='prayer' AND source_id=p_prayer_id;
  IF item.id IS NULL OR NOT public.circle_feed_item_visible(item.id) THEN RAISE EXCEPTION 'Prayer access required'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',update_row.id,'prayerId',update_row.prayer_id,'authorPersonId',update_row.author_person_id,'authorName',concat_ws(' ',person.first_name,person.last_name),'type',update_row.update_type,'body',update_row.body,'createdAt',update_row.created_at,'updatedAt',update_row.updated_at,'canEdit',update_row.author_person_id=public.circle_current_person_id(item.organization_id),'canModerate',public.circle_feed_item_moderatable(item.id)) ORDER BY update_row.created_at,update_row.id),'[]'::jsonb)
  INTO result FROM public.circle_prayer_updates update_row JOIN public.people person ON person.id=update_row.author_person_id
  WHERE update_row.prayer_id=p_prayer_id AND update_row.hidden_at IS NULL;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_circle_community_profile(p_bio TEXT,p_bio_visibility TEXT,p_join_date_visibility TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_organization_id UUID; v_person_id UUID;
BEGIN
  IF char_length(btrim(coalesce(p_bio,'')))>500 OR p_bio_visibility NOT IN ('organization','shared_circle','hidden') OR p_join_date_visibility NOT IN ('organization','shared_circle','hidden') THEN RAISE EXCEPTION 'Invalid community profile'; END IF;
  SELECT link.organization_id,link.person_id INTO v_organization_id,v_person_id FROM public.circle_user_links link
  WHERE link.user_id=auth.uid() AND link.status='active' ORDER BY link.created_at LIMIT 1;
  IF v_person_id IS NULL THEN RAISE EXCEPTION 'Active community membership required'; END IF;
  INSERT INTO public.circle_community_profiles(organization_id,person_id,bio,bio_visibility,join_date_visibility)
  VALUES(v_organization_id,v_person_id,btrim(coalesce(p_bio,'')),p_bio_visibility,p_join_date_visibility)
  ON CONFLICT(organization_id,person_id) DO UPDATE SET bio=excluded.bio,bio_visibility=excluded.bio_visibility,join_date_visibility=excluded.join_date_visibility,updated_at=now();
END;
$$;

CREATE OR REPLACE FUNCTION public.get_circle_community_member_profile(p_person_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE target public.people%ROWTYPE; profile public.circle_community_profiles%ROWTYPE; result JSONB; viewer UUID;
BEGIN
  SELECT * INTO target FROM public.people WHERE id=p_person_id;
  IF target.id IS NULL OR NOT public.circle_has_active_org_access(target.organization_id) OR NOT EXISTS(SELECT 1 FROM public.circle_user_links link WHERE link.organization_id=target.organization_id AND link.person_id=target.id AND link.status='active') THEN RETURN NULL; END IF;
  viewer:=public.circle_current_person_id(target.organization_id);
  SELECT * INTO profile FROM public.circle_community_profiles WHERE organization_id=target.organization_id AND person_id=target.id;
  SELECT jsonb_build_object(
    'personId',target.id,'fullName',concat_ws(' ',target.first_name,target.last_name),
    'avatarUrl',(SELECT user_profile.avatar_url FROM public.circle_user_links link JOIN public.profiles user_profile ON user_profile.id=link.user_id WHERE link.organization_id=target.organization_id AND link.person_id=target.id AND link.status='active' LIMIT 1),
    'bio',CASE WHEN public.circle_can_view_profile_field(target.organization_id,target.id,coalesce(profile.bio_visibility,'organization')) THEN nullif(profile.bio,'') END,
    'bioVisibility',coalesce(profile.bio_visibility,'organization'),
    'joinDate',CASE WHEN public.circle_can_view_profile_field(target.organization_id,target.id,coalesce(profile.join_date_visibility,'hidden')) THEN target.join_date END,
    'joinDateVisibility',coalesce(profile.join_date_visibility,'hidden'),
    'circles',coalesce((SELECT jsonb_agg(jsonb_build_object('id',group_row.id,'name',group_row.name,'role',membership.role) ORDER BY group_row.name)
      FROM public.cell_group_members membership JOIN public.cell_groups group_row ON group_row.id=membership.cell_group_id
      WHERE membership.person_id=target.id AND group_row.status='active' AND public.circle_can_access_group(group_row.id)),'[]'::jsonb),
    'recentItems',coalesce((SELECT jsonb_agg(public.circle_feed_item_json_v2(recent.id) ORDER BY recent.activity_at DESC)
      FROM (SELECT item.id,item.activity_at FROM public.circle_feed_items item WHERE item.author_person_id=target.id AND public.circle_feed_item_personally_visible(item.id) ORDER BY item.activity_at DESC LIMIT 10) recent),'[]'::jsonb),
    'canEdit',target.id=viewer
  ) INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.search_circle_community_members(p_query TEXT DEFAULT '',p_limit INTEGER DEFAULT 50)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result JSONB; bounded_limit INTEGER:=least(greatest(coalesce(p_limit,50),1),100);
BEGIN
  SELECT coalesce(jsonb_agg(public.get_circle_community_member_profile(candidate.id) ORDER BY candidate.last_name,candidate.first_name),'[]'::jsonb) INTO result
  FROM (SELECT person.* FROM public.people person WHERE public.circle_has_active_org_access(person.organization_id)
    AND EXISTS(SELECT 1 FROM public.circle_user_links link WHERE link.organization_id=person.organization_id AND link.person_id=person.id AND link.status='active')
    AND (btrim(coalesce(p_query,''))='' OR concat_ws(' ',person.first_name,person.last_name) ILIKE '%'||btrim(p_query)||'%')
    ORDER BY person.last_name,person.first_name LIMIT bounded_limit) candidate;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.search_circle_community_feed(
  p_query TEXT DEFAULT NULL,p_type TEXT DEFAULT NULL,p_circle_id UUID DEFAULT NULL,p_author_person_id UUID DEFAULT NULL,p_saved_only BOOLEAN DEFAULT false,p_limit INTEGER DEFAULT 50
)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result JSONB; bounded_limit INTEGER:=least(greatest(coalesce(p_limit,50),1),100);
BEGIN
  IF p_type IS NOT NULL AND p_type NOT IN ('post','reflection','prayer','gathering','announcement') THEN RAISE EXCEPTION 'Unsupported feed type'; END IF;
  SELECT coalesce(jsonb_agg(public.circle_feed_item_json_v2(candidate.id) ORDER BY candidate.activity_at DESC,candidate.id DESC),'[]'::jsonb) INTO result
  FROM (SELECT item.id,item.activity_at FROM public.circle_feed_items item
    LEFT JOIN public.people person ON person.id=item.author_person_id
    LEFT JOIN public.circle_feed_posts post ON item.source_type='post' AND post.id=item.source_id
    LEFT JOIN public.circle_gathering_reflections reflection ON item.source_type='reflection' AND reflection.id=item.source_id
    LEFT JOIN public.circle_prayer_requests prayer ON item.source_type='prayer' AND prayer.id=item.source_id
    LEFT JOIN public.circle_gatherings gathering ON item.source_type='gathering' AND gathering.id=item.source_id
    LEFT JOIN public.circle_announcements announcement ON item.source_type='announcement' AND announcement.id=item.source_id
    WHERE public.circle_feed_item_personally_visible(item.id)
      AND (p_type IS NULL OR item.source_type=p_type) AND (p_circle_id IS NULL OR item.cell_group_id=p_circle_id)
      AND (p_author_person_id IS NULL OR item.author_person_id=p_author_person_id)
      AND (NOT p_saved_only OR EXISTS(SELECT 1 FROM public.circle_feed_saves saved WHERE saved.feed_item_id=item.id AND saved.person_id=public.circle_current_person_id(item.organization_id)))
      AND (btrim(coalesce(p_query,''))='' OR concat_ws(' ',person.first_name,person.last_name,post.body,reflection.body,prayer.title,prayer.description,gathering.title,announcement.title,announcement.body) ILIKE '%'||btrim(p_query)||'%')
    ORDER BY item.activity_at DESC,item.id DESC LIMIT bounded_limit) candidate;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_circle_community_feed_seen()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_organization_id UUID; v_person_id UUID;
BEGIN
  SELECT link.organization_id,link.person_id INTO v_organization_id,v_person_id FROM public.circle_user_links link WHERE link.user_id=auth.uid() AND link.status='active' ORDER BY link.created_at LIMIT 1;
  IF v_person_id IS NULL THEN RAISE EXCEPTION 'Active community membership required'; END IF;
  INSERT INTO public.circle_feed_read_state(organization_id,person_id,last_seen_at) VALUES(v_organization_id,v_person_id,now())
  ON CONFLICT(organization_id,person_id) DO UPDATE SET last_seen_at=excluded.last_seen_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.circle_prepare_feed_comment()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  NEW.body:=btrim(NEW.body);
  IF TG_OP='INSERT' AND NOT EXISTS(SELECT 1 FROM public.circle_feed_items item WHERE item.id=NEW.feed_item_id AND item.comments_enabled) THEN RAISE EXCEPTION 'Comments are closed'; END IF;
  IF TG_OP='UPDATE' THEN NEW.updated_at:=now(); END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.circle_resurface_prayer_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE;
BEGIN
  SELECT * INTO item FROM public.circle_feed_items WHERE source_type='prayer' AND source_id=NEW.prayer_id;
  UPDATE public.circle_feed_items SET activity_at=NEW.created_at WHERE id=item.id;
  INSERT INTO public.circle_feed_notifications(organization_id,recipient_person_id,feed_item_id,kind,latest_actor_person_id,prayer_update_id)
  SELECT item.organization_id,subscription.person_id,item.id,'prayer_update',NEW.author_person_id,NEW.id
  FROM public.circle_feed_subscriptions subscription WHERE subscription.feed_item_id=item.id AND subscription.person_id<>NEW.author_person_id
  ON CONFLICT(recipient_person_id,feed_item_id,kind) DO UPDATE SET latest_actor_person_id=excluded.latest_actor_person_id,actor_count=circle_feed_notifications.actor_count+1,read_at=NULL,updated_at=now(),prayer_update_id=excluded.prayer_update_id;
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_prayer_updates_resurface AFTER INSERT ON public.circle_prayer_updates
FOR EACH ROW EXECUTE FUNCTION public.circle_resurface_prayer_update();

CREATE OR REPLACE FUNCTION public.circle_notify_feed_reaction()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item public.circle_feed_items%ROWTYPE;
BEGIN
  IF TG_OP<>'INSERT' THEN RETURN NEW; END IF;
  SELECT * INTO item FROM public.circle_feed_items WHERE id=NEW.feed_item_id;
  IF item.author_person_id IS NULL OR item.author_person_id=NEW.person_id THEN RETURN NEW; END IF;
  INSERT INTO public.circle_feed_notifications(organization_id,recipient_person_id,feed_item_id,kind,latest_actor_person_id)
  VALUES(item.organization_id,item.author_person_id,item.id,'reaction',NEW.person_id)
  ON CONFLICT(recipient_person_id,feed_item_id,kind) DO UPDATE SET latest_actor_person_id=excluded.latest_actor_person_id,actor_count=circle_feed_notifications.actor_count+1,read_at=NULL,updated_at=now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER circle_feed_reactions_notify AFTER INSERT ON public.circle_feed_reactions
FOR EACH ROW EXECUTE FUNCTION public.circle_notify_feed_reaction();

CREATE OR REPLACE FUNCTION public.get_circle_feed_notifications(p_before_updated_at TIMESTAMPTZ DEFAULT NULL,p_before_id UUID DEFAULT NULL,p_limit INTEGER DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result JSONB; bounded_limit INTEGER:=least(greatest(coalesce(p_limit,30),1),100);
BEGIN
  WITH visible AS (
    SELECT notice.updated_at,notice.id,jsonb_build_object('id',notice.id,'feedItemId',notice.feed_item_id,'kind',notice.kind,'actorCount',notice.actor_count,'actorName',concat_ws(' ',person.first_name,person.last_name),'readAt',notice.read_at,'createdAt',notice.updated_at,'targetCommentId',notice.target_comment_id,'prayerUpdateId',notice.prayer_update_id) payload
    FROM public.circle_feed_notifications notice JOIN public.people person ON person.id=notice.latest_actor_person_id
    WHERE notice.recipient_person_id=public.circle_current_person_id(notice.organization_id)
      AND (p_before_updated_at IS NULL OR (notice.updated_at,notice.id)<(p_before_updated_at,p_before_id))
    ORDER BY notice.updated_at DESC,notice.id DESC LIMIT bounded_limit+1
  ), selected AS (SELECT * FROM visible ORDER BY updated_at DESC,id DESC LIMIT bounded_limit)
  SELECT jsonb_build_object('notifications',coalesce(jsonb_agg(payload ORDER BY updated_at DESC,id DESC),'[]'::jsonb),
    'nextCursor',CASE WHEN (SELECT count(*) FROM visible)>bounded_limit THEN (SELECT jsonb_build_object('createdAt',updated_at,'id',id) FROM visible ORDER BY updated_at DESC,id DESC OFFSET bounded_limit-1 LIMIT 1) END)
  INTO result FROM selected;
  RETURN coalesce(result,'{"notifications":[],"nextCursor":null}'::jsonb);
END;
$$;

REVOKE ALL ON public.circle_community_profiles,public.circle_feed_reactions,public.circle_feed_saves,public.circle_feed_hidden_items,public.circle_feed_subscriptions,public.circle_feed_read_state,public.circle_feed_pins,public.circle_feed_reports,public.circle_feed_report_actions,public.circle_prayer_updates FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.circle_feed_item_personally_visible(UUID),public.circle_can_view_profile_field(UUID,UUID,TEXT),public.circle_feed_item_json_v2(UUID),public.circle_sync_legacy_like_to_reaction(),public.circle_sync_reaction_to_legacy_like(),public.circle_resurface_prayer_update(),public.circle_notify_feed_reaction() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_circle_community_feed_v2(TIMESTAMPTZ,UUID,TIMESTAMPTZ,INTEGER,UUID,BOOLEAN),public.get_circle_community_feed_item(UUID),public.set_circle_feed_reaction(UUID,TEXT),public.set_circle_feed_saved(UUID,BOOLEAN),public.set_circle_feed_personally_hidden(UUID,BOOLEAN),public.report_circle_feed_item(UUID,TEXT,TEXT),public.set_circle_feed_comments_enabled(UUID,BOOLEAN),public.set_circle_feed_pinned(UUID,BOOLEAN),public.set_circle_prayer_follow(UUID,BOOLEAN),public.add_circle_prayer_update(UUID,TEXT,TEXT),public.get_circle_prayer_updates(UUID),public.upsert_circle_community_profile(TEXT,TEXT,TEXT),public.get_circle_community_member_profile(UUID),public.search_circle_community_members(TEXT,INTEGER),public.search_circle_community_feed(TEXT,TEXT,UUID,UUID,BOOLEAN,INTEGER),public.mark_circle_community_feed_seen() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_circle_community_feed_v2(TIMESTAMPTZ,UUID,TIMESTAMPTZ,INTEGER,UUID,BOOLEAN),public.get_circle_community_feed_item(UUID),public.set_circle_feed_reaction(UUID,TEXT),public.set_circle_feed_saved(UUID,BOOLEAN),public.set_circle_feed_personally_hidden(UUID,BOOLEAN),public.report_circle_feed_item(UUID,TEXT,TEXT),public.set_circle_feed_comments_enabled(UUID,BOOLEAN),public.set_circle_feed_pinned(UUID,BOOLEAN),public.set_circle_prayer_follow(UUID,BOOLEAN),public.add_circle_prayer_update(UUID,TEXT,TEXT),public.get_circle_prayer_updates(UUID),public.upsert_circle_community_profile(TEXT,TEXT,TEXT),public.get_circle_community_member_profile(UUID),public.search_circle_community_members(TEXT,INTEGER),public.search_circle_community_feed(TEXT,TEXT,UUID,UUID,BOOLEAN,INTEGER),public.mark_circle_community_feed_seen() TO authenticated;

COMMIT;
