BEGIN;

CREATE TABLE public.circle_gathering_reflections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  gathering_id UUID NOT NULL REFERENCES public.circle_gatherings(id) ON DELETE CASCADE,
  author_person_id UUID NOT NULL REFERENCES public.people(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 2000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX circle_gathering_reflections_gathering_created_idx
  ON public.circle_gathering_reflections(gathering_id, created_at);
CREATE INDEX circle_gathering_reflections_author_idx
  ON public.circle_gathering_reflections(author_person_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.prepare_circle_gathering_reflection()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
  gathering public.circle_gatherings%ROWTYPE;
BEGIN
  NEW.body := btrim(NEW.body);
  IF TG_OP = 'UPDATE' THEN
    IF NEW.organization_id <> OLD.organization_id
      OR NEW.gathering_id <> OLD.gathering_id
      OR NEW.author_person_id <> OLD.author_person_id
      OR NEW.created_at <> OLD.created_at THEN
      RAISE EXCEPTION 'Reflection ownership and gathering cannot be changed';
    END IF;
    NEW.updated_at := now();
  END IF;

  SELECT * INTO gathering
  FROM public.circle_gatherings
  WHERE id = NEW.gathering_id;

  IF gathering.id IS NULL OR gathering.organization_id <> NEW.organization_id THEN
    RAISE EXCEPTION 'Reflection gathering and organization must match';
  END IF;
  IF gathering.status <> 'completed' THEN
    RAISE EXCEPTION 'Reflections are available after a gathering is completed';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER circle_gathering_reflections_prepare
BEFORE INSERT OR UPDATE ON public.circle_gathering_reflections
FOR EACH ROW EXECUTE FUNCTION public.prepare_circle_gathering_reflection();

ALTER TABLE public.circle_gathering_reflections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gathering audiences read completed reflections"
ON public.circle_gathering_reflections FOR SELECT TO authenticated
USING (
  public.circle_can_access_gathering(gathering_id)
  AND EXISTS (
    SELECT 1 FROM public.circle_gatherings gathering
    WHERE gathering.id = circle_gathering_reflections.gathering_id
      AND gathering.organization_id = circle_gathering_reflections.organization_id
      AND gathering.status = 'completed'
  )
);

CREATE POLICY "Members create own completed gathering reflections"
ON public.circle_gathering_reflections FOR INSERT TO authenticated
WITH CHECK (
  author_person_id = public.circle_current_person_id(organization_id)
  AND public.circle_can_access_gathering(gathering_id)
  AND EXISTS (
    SELECT 1 FROM public.circle_gatherings gathering
    WHERE gathering.id = circle_gathering_reflections.gathering_id
      AND gathering.organization_id = circle_gathering_reflections.organization_id
      AND gathering.status = 'completed'
  )
);

CREATE POLICY "Members edit own completed gathering reflections"
ON public.circle_gathering_reflections FOR UPDATE TO authenticated
USING (author_person_id = public.circle_current_person_id(organization_id))
WITH CHECK (
  author_person_id = public.circle_current_person_id(organization_id)
  AND public.circle_can_access_gathering(gathering_id)
  AND EXISTS (
    SELECT 1 FROM public.circle_gatherings gathering
    WHERE gathering.id = circle_gathering_reflections.gathering_id
      AND gathering.organization_id = circle_gathering_reflections.organization_id
      AND gathering.status = 'completed'
  )
);

CREATE POLICY "Authors and gathering managers delete reflections"
ON public.circle_gathering_reflections FOR DELETE TO authenticated
USING (
  author_person_id = public.circle_current_person_id(organization_id)
  OR public.circle_can_manage_gathering(gathering_id)
);

REVOKE ALL ON public.circle_gathering_reflections FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.circle_gathering_reflections TO authenticated;
REVOKE ALL ON FUNCTION public.prepare_circle_gathering_reflection() FROM PUBLIC, anon, authenticated;

COMMIT;
