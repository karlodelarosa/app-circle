CREATE OR REPLACE FUNCTION public.get_circle_public_sitemap()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT COALESCE(jsonb_agg(url ORDER BY url),'[]'::jsonb)
  FROM (
    SELECT '/'||organization.slug AS url
    FROM public.circle_public_spaces space
    JOIN public.organizations organization ON organization.id=space.organization_id
    WHERE space.is_published AND organization.status='active'
    UNION ALL
    SELECT '/'||organization.slug||'/gatherings/'||gathering.public_slug
    FROM public.circle_gatherings gathering
    JOIN public.organizations organization ON organization.id=gathering.organization_id
    JOIN public.circle_public_spaces space ON space.organization_id=organization.id
    WHERE space.is_published AND organization.status='active'
      AND gathering.visibility='public' AND gathering.published_at IS NOT NULL
      AND gathering.public_slug IS NOT NULL AND gathering.status='scheduled'
  ) public_urls;
$$;

REVOKE ALL ON FUNCTION public.get_circle_public_sitemap() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_circle_public_sitemap() TO anon,authenticated;
