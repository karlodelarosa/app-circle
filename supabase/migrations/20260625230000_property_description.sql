-- Optional item description (brand, model, specs, etc.)

ALTER TABLE public.church_properties
  ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
