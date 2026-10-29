-- Track completion timestamp for discipleship badge awards

ALTER TABLE public.discipleship_enrollments
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
