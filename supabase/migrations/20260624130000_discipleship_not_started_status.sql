-- Add "not_started" program lifecycle status for discipleship tracks

ALTER TABLE public.discipleship_tracks
  DROP CONSTRAINT IF EXISTS discipleship_tracks_status_check;
ALTER TABLE public.discipleship_tracks
  ADD CONSTRAINT discipleship_tracks_status_check
  CHECK (status IN ('not_started', 'active', 'finished'));
