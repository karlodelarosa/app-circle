-- Circles public/member MVP. Additive: preserves the original integration data.
-- This repository owns future circle_* migrations. Do not copy this migration
-- into SheepCount's migration stream.

BEGIN;

ALTER TABLE public.circle_gatherings
  ADD COLUMN IF NOT EXISTS public_slug TEXT,
  ADD COLUMN IF NOT EXISTS summary TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS cover_url TEXT,
  ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'public')),
  ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS guest_rsvp_enabled BOOLEAN NOT NULL DEFAULT false;

UPDATE public.circle_gatherings
SET public_slug = lower(regexp_replace(title, '[^a-zA-Z0-9]+', '-', 'g')) || '-' || left(id::text, 8)
WHERE public_slug IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS circle_gatherings_org_slug_idx ON public.circle_gatherings(organization_id, public_slug);
CREATE INDEX IF NOT EXISTS circle_gatherings_public_idx ON public.circle_gatherings(organization_id, visibility, starts_at) WHERE published_at IS NOT NULL;

ALTER TABLE public.circle_gathering_rsvps ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE;
UPDATE public.circle_gathering_rsvps r SET organization_id = g.organization_id FROM public.circle_gatherings g WHERE g.id = r.gathering_id AND r.organization_id IS NULL;
ALTER TABLE public.circle_gathering_rsvps ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.circle_prayer_clicks ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE;
UPDATE public.circle_prayer_clicks c SET organization_id = p.organization_id FROM public.circle_prayer_requests p WHERE p.id = c.prayer_id AND c.organization_id IS NULL;
ALTER TABLE public.circle_prayer_clicks ALTER COLUMN organization_id SET NOT NULL;

CREATE TABLE IF NOT EXISTS public.circle_public_spaces (
  organization_id UUID PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
  introduction TEXT NOT NULL DEFAULT '' CHECK (char_length(introduction) <= 800),
  hero_title TEXT NOT NULL DEFAULT 'There is room for you here.' CHECK (char_length(hero_title) <= 120),
  hero_image_url TEXT,
  is_published BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.circle_guest_rsvps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  gathering_id UUID NOT NULL REFERENCES public.circle_gatherings(id) ON DELETE CASCADE,
  guest_name TEXT NOT NULL CHECK (char_length(guest_name) BETWEEN 1 AND 120), email TEXT NOT NULL DEFAULT '', phone TEXT NOT NULL DEFAULT '',
  normalized_contact TEXT NOT NULL, status TEXT NOT NULL CHECK (status IN ('attending','tentative','declined')),
  attended_at TIMESTAMPTZ, converted_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(gathering_id, normalized_contact)
);
CREATE TABLE IF NOT EXISTS public.circle_testimonies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE SET NULL, author_person_id UUID REFERENCES public.people(id) ON DELETE SET NULL,
  author_display_name TEXT NOT NULL CHECK (char_length(author_display_name) BETWEEN 1 AND 120), public_slug TEXT NOT NULL,
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 160), body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 8000), image_url TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')), published_at TIMESTAMPTZ,
  created_by UUID NOT NULL REFERENCES auth.users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(organization_id, public_slug)
);
CREATE TABLE IF NOT EXISTS public.circle_galleries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  gathering_id UUID REFERENCES public.circle_gatherings(id) ON DELETE SET NULL, cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE SET NULL,
  public_slug TEXT NOT NULL, title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 160), description TEXT NOT NULL DEFAULT '', cover_url TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')), published_at TIMESTAMPTZ,
  created_by UUID NOT NULL REFERENCES auth.users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(organization_id, public_slug)
);
CREATE TABLE IF NOT EXISTS public.circle_gallery_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  gallery_id UUID NOT NULL REFERENCES public.circle_galleries(id) ON DELETE CASCADE, image_url TEXT NOT NULL, caption TEXT NOT NULL DEFAULT '',
  alt_text TEXT NOT NULL CHECK (char_length(alt_text) BETWEEN 1 AND 300), display_order INT NOT NULL DEFAULT 0, is_published BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.circle_public_listings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID NOT NULL UNIQUE REFERENCES public.cell_groups(id) ON DELETE CASCADE, public_slug TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '', cover_url TEXT, is_published BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(organization_id, public_slug)
);
CREATE TABLE IF NOT EXISTS public.circle_join_interests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  listing_id UUID NOT NULL REFERENCES public.circle_public_listings(id) ON DELETE CASCADE, name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  contact TEXT NOT NULL CHECK (char_length(contact) BETWEEN 3 AND 200), message TEXT NOT NULL DEFAULT '' CHECK (char_length(message) <= 1000),
  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','contacted','closed')), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.circle_announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  cell_group_id UUID REFERENCES public.cell_groups(id) ON DELETE CASCADE, title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 160),
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000), published_at TIMESTAMPTZ NOT NULL DEFAULT now(), expires_at TIMESTAMPTZ,
  created_by UUID NOT NULL REFERENCES auth.users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS circle_guest_rsvps_org_gathering_idx ON public.circle_guest_rsvps(organization_id,gathering_id);
CREATE INDEX IF NOT EXISTS circle_testimonies_public_idx ON public.circle_testimonies(organization_id,published_at DESC) WHERE status='published';
CREATE INDEX IF NOT EXISTS circle_galleries_public_idx ON public.circle_galleries(organization_id,published_at DESC) WHERE status='published';
CREATE INDEX IF NOT EXISTS circle_announcements_scope_idx ON public.circle_announcements(organization_id,cell_group_id,published_at DESC);

CREATE OR REPLACE FUNCTION public.circle_can_access_group(p_cell_group_id UUID) RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.cell_groups cg WHERE cg.id=p_cell_group_id AND (public.circle_is_org_admin(cg.organization_id) OR EXISTS(
   SELECT 1 FROM public.circle_user_links cul JOIN public.cell_group_members cgm ON cgm.person_id=cul.person_id
   WHERE cul.organization_id=cg.organization_id AND cul.user_id=auth.uid() AND cul.status='active' AND cgm.cell_group_id=cg.id)));
$$;
CREATE OR REPLACE FUNCTION public.circle_can_lead_group(p_cell_group_id UUID) RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.cell_groups cg WHERE cg.id=p_cell_group_id AND (public.circle_is_org_admin(cg.organization_id) OR EXISTS(
   SELECT 1 FROM public.circle_user_links cul LEFT JOIN public.cell_group_members cgm ON cgm.person_id=cul.person_id AND cgm.cell_group_id=cg.id
   WHERE cul.organization_id=cg.organization_id AND cul.user_id=auth.uid() AND cul.status='active' AND (cgm.role='Leader' OR cg.leader_person_id=cul.person_id))));
$$;

DROP POLICY IF EXISTS "Circle leaders create gatherings" ON public.circle_gatherings;
CREATE POLICY "Circle leaders create gatherings" ON public.circle_gatherings FOR INSERT TO authenticated WITH CHECK(created_by=auth.uid() AND public.circle_can_lead_group(cell_group_id) AND EXISTS(SELECT 1 FROM public.cell_groups cg WHERE cg.id=cell_group_id AND cg.organization_id=circle_gatherings.organization_id));
DROP POLICY IF EXISTS "Circle leaders update gatherings" ON public.circle_gatherings;
CREATE POLICY "Circle leaders update gatherings" ON public.circle_gatherings FOR UPDATE TO authenticated USING(public.circle_can_lead_group(cell_group_id)) WITH CHECK(public.circle_can_lead_group(cell_group_id) AND EXISTS(SELECT 1 FROM public.cell_groups cg WHERE cg.id=cell_group_id AND cg.organization_id=circle_gatherings.organization_id));
DROP POLICY IF EXISTS "Circle members create own RSVP" ON public.circle_gathering_rsvps;
CREATE POLICY "Circle members create own RSVP" ON public.circle_gathering_rsvps FOR INSERT TO authenticated WITH CHECK(EXISTS(SELECT 1 FROM public.circle_gatherings g WHERE g.id=gathering_id AND g.organization_id=circle_gathering_rsvps.organization_id AND public.circle_can_access_group(g.cell_group_id) AND person_id=public.circle_current_person_id(g.organization_id)));
DROP POLICY IF EXISTS "Circle members update own RSVP" ON public.circle_gathering_rsvps;
CREATE POLICY "Circle members update own RSVP" ON public.circle_gathering_rsvps FOR UPDATE TO authenticated USING(EXISTS(SELECT 1 FROM public.circle_gatherings g WHERE g.id=gathering_id AND g.organization_id=circle_gathering_rsvps.organization_id AND person_id=public.circle_current_person_id(g.organization_id))) WITH CHECK(EXISTS(SELECT 1 FROM public.circle_gatherings g WHERE g.id=gathering_id AND g.organization_id=circle_gathering_rsvps.organization_id AND person_id=public.circle_current_person_id(g.organization_id)));

CREATE OR REPLACE FUNCTION public.get_my_circle_context() RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_user UUID:=auth.uid(); v_org UUID; v_person UUID; v_admin BOOLEAN:=false; v_result JSONB;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT om.organization_id,(om.role='admin') INTO v_org,v_admin FROM public.organization_members om WHERE om.user_id=v_user AND om.status='active' ORDER BY (om.role='admin') DESC,om.created_at LIMIT 1;
 IF v_org IS NULL THEN RAISE EXCEPTION 'No active SheepCount organization is linked to this account'; END IF;
 SELECT cul.person_id INTO v_person FROM public.circle_user_links cul WHERE cul.organization_id=v_org AND cul.user_id=v_user AND cul.status='active' LIMIT 1;
 SELECT jsonb_build_object('organization',jsonb_build_object('id',o.id,'name',o.name,'slug',o.slug,'image',o.image,'status',o.status),'circlesEnabled',true,'isAdmin',v_admin,'personId',v_person,
 'profile',jsonb_build_object('id',p.id,'firstName',p.first_name,'lastName',p.last_name,'avatarUrl',p.avatar_url),
 'groups',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',cg.id,'name',cg.name,'description',cg.description,'location',cg.location,'leaderPersonId',cg.leader_person_id,'status',cg.status,'role',CASE WHEN v_admin THEN 'admin' WHEN cgm.role='Leader' OR cg.leader_person_id=v_person THEN 'leader' ELSE 'member' END) ORDER BY cg.name)
 FROM public.cell_groups cg LEFT JOIN public.cell_group_members cgm ON cgm.cell_group_id=cg.id AND cgm.person_id=v_person WHERE cg.organization_id=o.id AND cg.status='active' AND (v_admin OR cgm.id IS NOT NULL OR cg.leader_person_id=v_person)),'[]'::jsonb)) INTO v_result
 FROM public.organizations o LEFT JOIN public.profiles p ON p.id=v_user WHERE o.id=v_org; RETURN v_result;
END; $$;

ALTER TABLE public.circle_public_spaces ENABLE ROW LEVEL SECURITY; ALTER TABLE public.circle_guest_rsvps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_testimonies ENABLE ROW LEVEL SECURITY; ALTER TABLE public.circle_galleries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_gallery_photos ENABLE ROW LEVEL SECURITY; ALTER TABLE public.circle_public_listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_join_interests ENABLE ROW LEVEL SECURITY; ALTER TABLE public.circle_announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Published Circle spaces are public" ON public.circle_public_spaces;
DROP POLICY IF EXISTS "Org admins manage Circle spaces" ON public.circle_public_spaces;
DROP POLICY IF EXISTS "Published testimonies are public" ON public.circle_testimonies;
DROP POLICY IF EXISTS "Published galleries are public" ON public.circle_galleries;
DROP POLICY IF EXISTS "Published gallery photos are public" ON public.circle_gallery_photos;
DROP POLICY IF EXISTS "Published Circle listings are public" ON public.circle_public_listings;
DROP POLICY IF EXISTS "Leaders manage testimonies" ON public.circle_testimonies;
DROP POLICY IF EXISTS "Leaders manage galleries" ON public.circle_galleries;
DROP POLICY IF EXISTS "Leaders manage gallery photos" ON public.circle_gallery_photos;
DROP POLICY IF EXISTS "Leaders manage Circle listings" ON public.circle_public_listings;
DROP POLICY IF EXISTS "Leaders manage announcements" ON public.circle_announcements;
DROP POLICY IF EXISTS "Leaders read guest RSVPs" ON public.circle_guest_rsvps;
DROP POLICY IF EXISTS "Leaders read join interests" ON public.circle_join_interests;
DROP POLICY IF EXISTS "Circle members read announcements" ON public.circle_announcements;

CREATE POLICY "Published Circle spaces are public" ON public.circle_public_spaces FOR SELECT TO anon,authenticated USING(is_published);
CREATE POLICY "Org admins manage Circle spaces" ON public.circle_public_spaces FOR ALL TO authenticated USING(public.circle_is_org_admin(organization_id)) WITH CHECK(public.circle_is_org_admin(organization_id));
CREATE POLICY "Published testimonies are public" ON public.circle_testimonies FOR SELECT TO anon,authenticated USING(status='published' AND EXISTS(SELECT 1 FROM public.circle_public_spaces s WHERE s.organization_id=circle_testimonies.organization_id AND s.is_published));
CREATE POLICY "Published galleries are public" ON public.circle_galleries FOR SELECT TO anon,authenticated USING(status='published' AND EXISTS(SELECT 1 FROM public.circle_public_spaces s WHERE s.organization_id=circle_galleries.organization_id AND s.is_published));
CREATE POLICY "Published gallery photos are public" ON public.circle_gallery_photos FOR SELECT TO anon,authenticated USING(is_published AND EXISTS(SELECT 1 FROM public.circle_galleries g JOIN public.circle_public_spaces s ON s.organization_id=g.organization_id WHERE g.id=gallery_id AND g.status='published' AND s.is_published));
CREATE POLICY "Published Circle listings are public" ON public.circle_public_listings FOR SELECT TO anon,authenticated USING(is_published AND EXISTS(SELECT 1 FROM public.circle_public_spaces s WHERE s.organization_id=circle_public_listings.organization_id AND s.is_published));
CREATE POLICY "Leaders manage testimonies" ON public.circle_testimonies FOR ALL TO authenticated USING(public.circle_is_org_admin(organization_id) OR (cell_group_id IS NOT NULL AND public.circle_can_lead_group(cell_group_id))) WITH CHECK(public.circle_is_org_admin(organization_id) OR (cell_group_id IS NOT NULL AND public.circle_can_lead_group(cell_group_id)));
CREATE POLICY "Leaders manage galleries" ON public.circle_galleries FOR ALL TO authenticated USING(public.circle_is_org_admin(organization_id) OR (cell_group_id IS NOT NULL AND public.circle_can_lead_group(cell_group_id))) WITH CHECK(public.circle_is_org_admin(organization_id) OR (cell_group_id IS NOT NULL AND public.circle_can_lead_group(cell_group_id)));
CREATE POLICY "Leaders manage gallery photos" ON public.circle_gallery_photos FOR ALL TO authenticated USING(EXISTS(SELECT 1 FROM public.circle_galleries g WHERE g.id=gallery_id AND (public.circle_is_org_admin(g.organization_id) OR (g.cell_group_id IS NOT NULL AND public.circle_can_lead_group(g.cell_group_id))))) WITH CHECK(EXISTS(SELECT 1 FROM public.circle_galleries g WHERE g.id=gallery_id AND (public.circle_is_org_admin(g.organization_id) OR (g.cell_group_id IS NOT NULL AND public.circle_can_lead_group(g.cell_group_id)))));
CREATE POLICY "Leaders manage Circle listings" ON public.circle_public_listings FOR ALL TO authenticated USING(public.circle_is_org_admin(organization_id) OR public.circle_can_lead_group(cell_group_id)) WITH CHECK(public.circle_is_org_admin(organization_id) OR public.circle_can_lead_group(cell_group_id));
CREATE POLICY "Leaders manage announcements" ON public.circle_announcements FOR ALL TO authenticated USING(public.circle_is_org_admin(organization_id) OR (cell_group_id IS NOT NULL AND public.circle_can_lead_group(cell_group_id))) WITH CHECK(public.circle_is_org_admin(organization_id) OR (cell_group_id IS NOT NULL AND public.circle_can_lead_group(cell_group_id)));
CREATE POLICY "Leaders read guest RSVPs" ON public.circle_guest_rsvps FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.circle_gatherings g WHERE g.id=gathering_id AND public.circle_can_lead_group(g.cell_group_id)));
CREATE POLICY "Leaders read join interests" ON public.circle_join_interests FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.circle_public_listings l WHERE l.id=listing_id AND public.circle_can_lead_group(l.cell_group_id)));
CREATE POLICY "Circle members read announcements" ON public.circle_announcements FOR SELECT TO authenticated USING((cell_group_id IS NULL AND EXISTS(SELECT 1 FROM public.organization_members om WHERE om.organization_id=circle_announcements.organization_id AND om.user_id=auth.uid() AND om.status='active')) OR public.circle_can_access_group(cell_group_id));

CREATE OR REPLACE FUNCTION public.get_circle_public_space(p_org_slug TEXT) RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('organization',jsonb_build_object('id',o.id,'slug',o.slug,'name',o.name,'imageUrl',o.image,'subscriptionStatus',o.status,'circlesEnabled',true),
 'introduction',s.introduction,'heroTitle',s.hero_title,'heroImageUrl',s.hero_image_url,
 'gatherings',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',g.id,'organizationId',g.organization_id,'groupId',g.cell_group_id,'slug',g.public_slug,'title',g.title,'meetingDate',g.starts_at,'location',g.location,'studyTopic',g.study_topic,'notes',g.notes,'summary',g.summary,'coverUrl',g.cover_url,'status',g.status,'createdBy',g.created_by,'visibility',g.visibility,'publishedAt',g.published_at,'guestRsvpEnabled',g.guest_rsvp_enabled,'rsvps','{}'::jsonb) ORDER BY g.starts_at) FROM public.circle_gatherings g WHERE g.organization_id=o.id AND g.visibility='public' AND g.published_at IS NOT NULL AND g.status='scheduled'),'[]'::jsonb),
 'testimonies',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'organizationId',t.organization_id,'groupId',t.cell_group_id,'slug',t.public_slug,'title',t.title,'body',t.body,'authorName',t.author_display_name,'imageUrl',t.image_url,'publishedAt',t.published_at) ORDER BY t.published_at DESC) FROM public.circle_testimonies t WHERE t.organization_id=o.id AND t.status='published'),'[]'::jsonb),
 'galleries',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',ga.id,'organizationId',ga.organization_id,'gatheringId',ga.gathering_id,'slug',ga.public_slug,'title',ga.title,'description',ga.description,'coverUrl',ga.cover_url,'publishedAt',ga.published_at,'photos',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',ph.id,'imageUrl',ph.image_url,'caption',ph.caption,'altText',ph.alt_text) ORDER BY ph.display_order) FROM public.circle_gallery_photos ph WHERE ph.gallery_id=ga.id AND ph.is_published),'[]'::jsonb)) ORDER BY ga.published_at DESC) FROM public.circle_galleries ga WHERE ga.organization_id=o.id AND ga.status='published'),'[]'::jsonb),
 'circles',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',cg.id,'organizationId',cg.organization_id,'slug',l.public_slug,'name',cg.name,'description',COALESCE(NULLIF(l.description,''),cg.description),'regularSchedule','','location',cg.location,'leaderId',cg.leader_person_id,'role','member','coverUrl',l.cover_url,'isPublic',true) ORDER BY cg.name) FROM public.circle_public_listings l JOIN public.cell_groups cg ON cg.id=l.cell_group_id WHERE l.organization_id=o.id AND l.is_published),'[]'::jsonb))
 FROM public.organizations o JOIN public.circle_public_spaces s ON s.organization_id=o.id AND s.is_published WHERE o.slug=p_org_slug AND o.status='active' LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.submit_circle_guest_rsvp(p_gathering_id UUID,p_name TEXT,p_email TEXT,p_phone TEXT,p_status TEXT) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE g public.circle_gatherings%ROWTYPE; contact TEXT; rid UUID;
BEGIN SELECT * INTO g FROM public.circle_gatherings WHERE id=p_gathering_id AND visibility='public' AND published_at IS NOT NULL AND guest_rsvp_enabled AND status='scheduled' AND EXISTS(SELECT 1 FROM public.circle_public_spaces s WHERE s.organization_id=circle_gatherings.organization_id AND s.is_published); IF g.id IS NULL THEN RAISE EXCEPTION 'Guest RSVP is unavailable'; END IF;
 IF nullif(trim(p_name),'') IS NULL OR p_status NOT IN('attending','tentative','declined') THEN RAISE EXCEPTION 'A valid name and response are required'; END IF;
 contact:=CASE WHEN nullif(lower(trim(p_email)),'') IS NOT NULL THEN 'email:'||lower(trim(p_email)) ELSE 'phone:'||regexp_replace(p_phone,'[^0-9+]','','g') END; IF contact IN('phone:','email:') THEN RAISE EXCEPTION 'Email or phone is required'; END IF;
 INSERT INTO public.circle_guest_rsvps(organization_id,gathering_id,guest_name,email,phone,normalized_contact,status) VALUES(g.organization_id,g.id,trim(p_name),lower(trim(p_email)),trim(p_phone),contact,p_status)
 ON CONFLICT(gathering_id,normalized_contact) DO UPDATE SET guest_name=excluded.guest_name,email=excluded.email,phone=excluded.phone,status=excluded.status,updated_at=now() RETURNING id INTO rid;
 RETURN jsonb_build_object('ok',true,'id',rid); END; $$;
CREATE OR REPLACE FUNCTION public.submit_circle_interest(p_listing_id UUID,p_name TEXT,p_contact TEXT,p_message TEXT) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE l public.circle_public_listings%ROWTYPE; rid UUID; BEGIN SELECT * INTO l FROM public.circle_public_listings WHERE id=p_listing_id AND is_published AND EXISTS(SELECT 1 FROM public.circle_public_spaces s WHERE s.organization_id=circle_public_listings.organization_id AND s.is_published); IF l.id IS NULL THEN RAISE EXCEPTION 'Circle listing unavailable'; END IF; IF nullif(trim(p_name),'') IS NULL OR char_length(trim(p_contact))<3 THEN RAISE EXCEPTION 'Name and contact are required'; END IF;
 INSERT INTO public.circle_join_interests(organization_id,listing_id,name,contact,message) VALUES(l.organization_id,l.id,trim(p_name),trim(p_contact),left(trim(p_message),1000)) RETURNING id INTO rid; RETURN jsonb_build_object('ok',true,'id',rid); END; $$;

CREATE OR REPLACE FUNCTION public.search_circle_people(p_organization_id UUID,p_cell_group_id UUID,p_query TEXT) RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'fullName',concat_ws(' ',p.first_name,p.last_name),'email',p.email,'phone',p.phone,'membershipType',p.membership_type,'alreadyInGroup',EXISTS(SELECT 1 FROM public.cell_group_members m WHERE m.cell_group_id=p_cell_group_id AND m.person_id=p.id)) ORDER BY p.last_name,p.first_name),'[]'::jsonb)
 FROM public.people p WHERE p.organization_id=p_organization_id AND EXISTS(SELECT 1 FROM public.cell_groups cg WHERE cg.id=p_cell_group_id AND cg.organization_id=p_organization_id) AND public.circle_can_lead_group(p_cell_group_id) AND (p.first_name ILIKE '%'||p_query||'%' OR p.last_name ILIKE '%'||p_query||'%' OR p.email ILIKE '%'||p_query||'%' OR p.phone ILIKE '%'||p_query||'%') LIMIT 30;
$$;
CREATE OR REPLACE FUNCTION public.add_person_to_cell_group(p_cell_group_id UUID,p_person_id UUID) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE oid UUID; BEGIN SELECT organization_id INTO oid FROM public.cell_groups WHERE id=p_cell_group_id; IF NOT public.circle_can_lead_group(p_cell_group_id) THEN RAISE EXCEPTION 'Leader access required'; END IF; IF NOT EXISTS(SELECT 1 FROM public.people WHERE id=p_person_id AND organization_id=oid) THEN RAISE EXCEPTION 'Person is outside this organization'; END IF; INSERT INTO public.cell_group_members(cell_group_id,person_id,role) VALUES(p_cell_group_id,p_person_id,'Member') ON CONFLICT(cell_group_id,person_id) DO NOTHING; END; $$;
CREATE OR REPLACE FUNCTION public.register_circle_visitor(p_cell_group_id UUID,p_first_name TEXT,p_last_name TEXT,p_email TEXT,p_phone TEXT,p_guest_rsvp_id UUID DEFAULT NULL) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE oid UUID; pid UUID; matched BOOLEAN:=false; BEGIN SELECT organization_id INTO oid FROM public.cell_groups WHERE id=p_cell_group_id; IF NOT public.circle_can_lead_group(p_cell_group_id) THEN RAISE EXCEPTION 'Leader access required'; END IF; IF nullif(trim(p_first_name),'') IS NULL OR nullif(trim(p_last_name),'') IS NULL OR (nullif(trim(p_email),'') IS NULL AND nullif(trim(p_phone),'') IS NULL) THEN RAISE EXCEPTION 'Name and email or phone are required'; END IF;
 SELECT id INTO pid FROM public.people WHERE organization_id=oid AND ((trim(p_email)<>'' AND lower(email)=lower(trim(p_email))) OR (trim(p_phone)<>'' AND phone=trim(p_phone))) ORDER BY created_at LIMIT 1; matched:=pid IS NOT NULL;
 IF pid IS NULL THEN INSERT INTO public.people(organization_id,household_id,first_name,last_name,email,phone,birthdate,role,status,membership_type,evangelism_stage,is_prospect,join_date) VALUES(oid,NULL,trim(p_first_name),trim(p_last_name),lower(trim(p_email)),trim(p_phone),NULL,'Single','Active','Prospect','Small Group',true,current_date) RETURNING id INTO pid; END IF;
 INSERT INTO public.cell_group_members(cell_group_id,person_id,role) VALUES(p_cell_group_id,pid,'Member') ON CONFLICT(cell_group_id,person_id) DO NOTHING; IF p_guest_rsvp_id IS NOT NULL THEN UPDATE public.circle_guest_rsvps SET converted_person_id=pid,updated_at=now() WHERE id=p_guest_rsvp_id AND organization_id=oid; END IF; RETURN jsonb_build_object('personId',pid,'matchedExisting',matched); END; $$;

CREATE OR REPLACE FUNCTION public.record_circle_attendance(p_gathering_id UUID,p_person_ids UUID[],p_guest_rsvp_ids UUID[] DEFAULT ARRAY[]::UUID[]) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE g public.circle_gatherings%ROWTYPE; grp public.cell_groups%ROWTYPE; sid UUID; leader_name TEXT;
BEGIN SELECT * INTO g FROM public.circle_gatherings WHERE id=p_gathering_id; IF g.id IS NULL OR NOT public.circle_can_lead_group(g.cell_group_id) THEN RAISE EXCEPTION 'Leader access required'; END IF; SELECT * INTO grp FROM public.cell_groups WHERE id=g.cell_group_id;
 IF EXISTS(SELECT 1 FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) x WHERE NOT EXISTS(SELECT 1 FROM public.people p WHERE p.id=x AND p.organization_id=g.organization_id)) THEN RAISE EXCEPTION 'An attendee is outside this organization'; END IF;
 SELECT concat_ws(' ',p.first_name,p.last_name) INTO leader_name FROM public.people p WHERE p.id=COALESCE(g.leader_person_id,grp.leader_person_id); leader_name:=COALESCE(nullif(leader_name,''),'Circle leader');
 INSERT INTO public.cell_group_sessions(organization_id,cell_group_id,session_date,leader_person_id,leader_name,location) VALUES(g.organization_id,g.cell_group_id,(g.starts_at AT TIME ZONE 'UTC')::date,COALESCE(g.leader_person_id,grp.leader_person_id),leader_name,g.location)
 ON CONFLICT(cell_group_id,session_date) DO UPDATE SET leader_person_id=excluded.leader_person_id,leader_name=excluded.leader_name,location=excluded.location,updated_at=now() RETURNING id INTO sid;
 DELETE FROM public.cell_group_session_attendees WHERE session_id=sid; INSERT INTO public.cell_group_session_attendees(session_id,person_id) SELECT sid,x FROM unnest(COALESCE(p_person_ids,ARRAY[]::UUID[])) x ON CONFLICT(session_id,person_id) DO NOTHING;
 UPDATE public.circle_guest_rsvps SET attended_at=now(),updated_at=now() WHERE gathering_id=g.id AND id=ANY(COALESCE(p_guest_rsvp_ids,ARRAY[]::UUID[])); UPDATE public.circle_gatherings SET attendance_session_id=sid,status='completed',updated_at=now() WHERE id=g.id; RETURN sid; END; $$;

INSERT INTO storage.buckets(id,name,public) VALUES('circle-public-media','circle-public-media',true) ON CONFLICT(id) DO UPDATE SET public=true;
DROP POLICY IF EXISTS "Public reads Circle media" ON storage.objects;
DROP POLICY IF EXISTS "Leaders upload Circle media" ON storage.objects;
DROP POLICY IF EXISTS "Leaders update Circle media" ON storage.objects;
DROP POLICY IF EXISTS "Leaders delete Circle media" ON storage.objects;
CREATE POLICY "Public reads Circle media" ON storage.objects FOR SELECT TO anon,authenticated USING(bucket_id='circle-public-media');
CREATE POLICY "Leaders upload Circle media" ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='circle-public-media' AND (public.circle_is_org_admin((storage.foldername(name))[1]::uuid) OR EXISTS(SELECT 1 FROM public.cell_groups cg WHERE cg.organization_id=(storage.foldername(name))[1]::uuid AND public.circle_can_lead_group(cg.id))));
CREATE POLICY "Leaders update Circle media" ON storage.objects FOR UPDATE TO authenticated USING(bucket_id='circle-public-media' AND (public.circle_is_org_admin((storage.foldername(name))[1]::uuid) OR EXISTS(SELECT 1 FROM public.cell_groups cg WHERE cg.organization_id=(storage.foldername(name))[1]::uuid AND public.circle_can_lead_group(cg.id))));
CREATE POLICY "Leaders delete Circle media" ON storage.objects FOR DELETE TO authenticated USING(bucket_id='circle-public-media' AND (public.circle_is_org_admin((storage.foldername(name))[1]::uuid) OR EXISTS(SELECT 1 FROM public.cell_groups cg WHERE cg.organization_id=(storage.foldername(name))[1]::uuid AND public.circle_can_lead_group(cg.id))));

REVOKE ALL ON FUNCTION public.get_circle_public_space(TEXT) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.get_circle_public_space(TEXT) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.submit_circle_guest_rsvp(UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.submit_circle_guest_rsvp(UUID,TEXT,TEXT,TEXT,TEXT) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.submit_circle_interest(UUID,TEXT,TEXT,TEXT) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.submit_circle_interest(UUID,TEXT,TEXT,TEXT) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.search_circle_people(UUID,UUID,TEXT) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.search_circle_people(UUID,UUID,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.add_person_to_cell_group(UUID,UUID) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.add_person_to_cell_group(UUID,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.register_circle_visitor(UUID,TEXT,TEXT,TEXT,TEXT,UUID) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.register_circle_visitor(UUID,TEXT,TEXT,TEXT,TEXT,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.record_circle_attendance(UUID,UUID[],UUID[]) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.record_circle_attendance(UUID,UUID[],UUID[]) TO authenticated;

COMMIT;
