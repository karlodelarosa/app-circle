-- Program lifecycle status for discipleship tracks (running vs finished cohort)

ALTER TABLE public.discipleship_tracks
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'discipleship_tracks_status_check'
      AND conrelid = 'public.discipleship_tracks'::regclass
  ) THEN
    ALTER TABLE public.discipleship_tracks
      ADD CONSTRAINT discipleship_tracks_status_check
      CHECK (status IN ('active', 'finished'));
  END IF;
END $$;
