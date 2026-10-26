BEGIN;

CREATE TABLE public.audit_event_types (
  code text PRIMARY KEY,
  description text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 300)
);
ALTER TABLE public.audit_event_types ENABLE ROW LEVEL SECURITY;

-- Campos cerrados: jamás almacenar aquí tokens, contraseñas o contenido de archivos.
CREATE TABLE public.audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  event_code text NOT NULL REFERENCES public.audit_event_types(code),
  device_id uuid,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (user_id, device_id) REFERENCES public.devices(user_id, id)
);
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;
CREATE INDEX audit_events_user_time_idx ON public.audit_events(user_id, occurred_at DESC);

REVOKE ALL ON public.audit_event_types, public.audit_events FROM PUBLIC, anon, authenticated;
COMMIT;
