BEGIN;

CREATE TABLE public.scan_statuses (
  code text PRIMARY KEY,
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 80)
);
ALTER TABLE public.scan_statuses ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.verdict_types (
  code text PRIMARY KEY,
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 80)
);
ALTER TABLE public.verdict_types ENABLE ROW LEVEL SECURITY;

-- Son agregados opcionales: jamás se almacenan aquí rutas ni contenido de archivos.
CREATE TABLE public.scan_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  device_id uuid NOT NULL,
  local_scan_id uuid NOT NULL,
  status_code text NOT NULL REFERENCES public.scan_statuses(code),
  files_discovered bigint NOT NULL CHECK (files_discovered >= 0),
  files_processed bigint NOT NULL CHECK (files_processed >= 0),
  files_error bigint NOT NULL CHECK (files_error >= 0),
  files_skipped bigint NOT NULL CHECK (files_skipped >= 0),
  schema_version integer NOT NULL DEFAULT 1 CHECK (schema_version = 1),
  started_at timestamptz NOT NULL,
  finished_at timestamptz,
  received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, id),
  UNIQUE (device_id, local_scan_id),
  FOREIGN KEY (user_id, device_id) REFERENCES public.devices(user_id, id) ON DELETE CASCADE,
  CHECK (finished_at IS NULL OR finished_at >= started_at),
  CHECK (files_processed <= files_discovered)
);
ALTER TABLE public.scan_runs ENABLE ROW LEVEL SECURITY;
CREATE INDEX scan_runs_user_time_idx ON public.scan_runs(user_id, started_at DESC);

CREATE TABLE public.scan_verdict_totals (
  user_id uuid NOT NULL,
  scan_id uuid NOT NULL,
  verdict_code text NOT NULL REFERENCES public.verdict_types(code),
  file_count bigint NOT NULL CHECK (file_count >= 0),
  PRIMARY KEY (user_id, scan_id, verdict_code),
  FOREIGN KEY (user_id, scan_id) REFERENCES public.scan_runs(user_id, id) ON DELETE CASCADE
);
ALTER TABLE public.scan_verdict_totals ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.scan_zones (
  code text PRIMARY KEY,
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 80)
);
ALTER TABLE public.scan_zones ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.scan_zone_totals (
  user_id uuid NOT NULL,
  scan_id uuid NOT NULL,
  zone_code text NOT NULL REFERENCES public.scan_zones(code),
  file_count bigint NOT NULL CHECK (file_count >= 0),
  PRIMARY KEY (user_id, scan_id, zone_code),
  FOREIGN KEY (user_id, scan_id) REFERENCES public.scan_runs(user_id, id) ON DELETE CASCADE
);
ALTER TABLE public.scan_zone_totals ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.detection_layers (
  code text PRIMARY KEY,
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 80)
);
ALTER TABLE public.detection_layers ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.scan_layer_totals (
  user_id uuid NOT NULL,
  scan_id uuid NOT NULL,
  layer_code text NOT NULL REFERENCES public.detection_layers(code),
  executions bigint NOT NULL CHECK (executions >= 0),
  hits bigint NOT NULL CHECK (hits >= 0),
  errors bigint NOT NULL CHECK (errors >= 0),
  PRIMARY KEY (user_id, scan_id, layer_code),
  FOREIGN KEY (user_id, scan_id) REFERENCES public.scan_runs(user_id, id) ON DELETE CASCADE,
  CHECK (hits <= executions AND errors <= executions)
);
ALTER TABLE public.scan_layer_totals ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.scan_statuses, public.verdict_types, public.scan_runs,
  public.scan_verdict_totals, public.scan_zones, public.scan_zone_totals,
  public.detection_layers, public.scan_layer_totals FROM PUBLIC, anon, authenticated;
COMMIT;
