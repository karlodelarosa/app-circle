-- A leader explicitly publishing a gathering also makes its invitation shell
-- available. Existing homepage copy and media are preserved.
BEGIN;

CREATE OR REPLACE FUNCTION public.circle_publish_space_for_public_gathering()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.visibility = 'public' AND NEW.published_at IS NOT NULL THEN
    INSERT INTO public.circle_public_spaces (organization_id, is_published)
    VALUES (NEW.organization_id, true)
    ON CONFLICT (organization_id) DO UPDATE
      SET is_published = true, updated_at = now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS circle_gatherings_publish_space ON public.circle_gatherings;
CREATE TRIGGER circle_gatherings_publish_space
  AFTER INSERT OR UPDATE OF visibility, published_at
  ON public.circle_gatherings
  FOR EACH ROW
  EXECUTE FUNCTION public.circle_publish_space_for_public_gathering();

INSERT INTO public.circle_public_spaces (organization_id, is_published)
SELECT DISTINCT organization_id, true
FROM public.circle_gatherings
WHERE visibility = 'public' AND published_at IS NOT NULL
ON CONFLICT (organization_id) DO UPDATE
  SET is_published = true, updated_at = now();

COMMIT;
