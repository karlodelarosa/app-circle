BEGIN;

-- Public submissions are RPC-only. Authenticated users read through RLS or
-- scoped RPCs and mutate only through the validated workflow functions.
REVOKE ALL ON TABLE public.circle_guest_connections FROM anon;
REVOKE ALL ON TABLE public.circle_guest_connection_activities FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.circle_guest_connections FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.circle_guest_connection_activities FROM authenticated;
GRANT SELECT ON TABLE public.circle_guest_connections TO authenticated;
GRANT SELECT ON TABLE public.circle_guest_connection_activities TO authenticated;

COMMIT;
