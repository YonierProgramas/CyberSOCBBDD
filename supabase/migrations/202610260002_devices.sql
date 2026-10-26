BEGIN;

CREATE TABLE public.device_platforms (
  code text PRIMARY KEY CHECK (code ~ '^[a-z0-9-]{2,40}$'),
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 80)
);
ALTER TABLE public.device_platforms ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  installation_id uuid NOT NULL,
  platform_code text NOT NULL REFERENCES public.device_platforms(code),
  display_name text NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 100),
  app_version text NOT NULL CHECK (char_length(app_version) BETWEEN 1 AND 60),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz,
  revoked_at timestamptz,
  UNIQUE (user_id, id),
  UNIQUE (user_id, installation_id),
  CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.device_settings (
  user_id uuid NOT NULL,
  device_id uuid NOT NULL,
  summary_sync_enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, device_id),
  FOREIGN KEY (user_id, device_id) REFERENCES public.devices(user_id, id) ON DELETE CASCADE
);
ALTER TABLE public.device_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.device_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  device_id uuid NOT NULL,
  event_code text NOT NULL CHECK (event_code IN ('LINKED', 'SEEN', 'UPDATED', 'REVOKED')),
  app_version text CHECK (char_length(app_version) BETWEEN 1 AND 60),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (user_id, device_id) REFERENCES public.devices(user_id, id) ON DELETE CASCADE
);
ALTER TABLE public.device_events ENABLE ROW LEVEL SECURITY;
CREATE INDEX device_events_device_time_idx ON public.device_events(user_id, device_id, occurred_at DESC);

-- No se almacenan códigos ni tokens en claro. La API debe limitar intentos y consumo.
CREATE TABLE public.device_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  code_hash text NOT NULL UNIQUE CHECK (code_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  CHECK (expires_at > created_at AND expires_at <= created_at + interval '15 minutes'),
  CHECK (consumed_at IS NULL OR (consumed_at >= created_at AND consumed_at < expires_at))
);
ALTER TABLE public.device_links ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.device_platforms, public.devices, public.device_settings,
  public.device_events, public.device_links FROM PUBLIC, anon, authenticated;
COMMIT;
