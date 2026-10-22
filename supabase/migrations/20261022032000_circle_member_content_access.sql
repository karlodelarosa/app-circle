BEGIN;

DROP POLICY IF EXISTS "Circle members read published testimonies" ON public.circle_testimonies;
CREATE POLICY "Circle members read published testimonies"
ON public.circle_testimonies FOR SELECT TO authenticated
USING (
  status = 'published'
  AND cell_group_id IS NOT NULL
  AND public.circle_can_access_group(cell_group_id)
);

DROP POLICY IF EXISTS "Circle members read published galleries" ON public.circle_galleries;
CREATE POLICY "Circle members read published galleries"
ON public.circle_galleries FOR SELECT TO authenticated
USING (
  status = 'published'
  AND cell_group_id IS NOT NULL
  AND public.circle_can_access_group(cell_group_id)
);

DROP POLICY IF EXISTS "Circle members read published gallery photos" ON public.circle_gallery_photos;
CREATE POLICY "Circle members read published gallery photos"
ON public.circle_gallery_photos FOR SELECT TO authenticated
USING (
  is_published
  AND EXISTS (
    SELECT 1
    FROM public.circle_galleries gallery
    WHERE gallery.id = circle_gallery_photos.gallery_id
      AND gallery.status = 'published'
      AND gallery.cell_group_id IS NOT NULL
      AND public.circle_can_access_group(gallery.cell_group_id)
  )
);

COMMIT;
