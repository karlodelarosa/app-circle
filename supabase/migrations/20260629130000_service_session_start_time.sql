ALTER TABLE public.service_sessions
  ADD COLUMN IF NOT EXISTS service_start_time TIME;
