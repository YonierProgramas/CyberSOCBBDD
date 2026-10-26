BEGIN;

CREATE TABLE public.report_formats (
  code text PRIMARY KEY,
  mime_type text NOT NULL CHECK (char_length(mime_type) BETWEEN 1 AND 100),
  extension text NOT NULL CHECK (extension ~ '^[a-z]{2,5}$')
);
ALTER TABLE public.report_formats ENABLE ROW LEVEL SECURITY;

-- Almacenamiento remoto opcional de reportes ya anonimizados, no de conversaciones.
CREATE TABLE public.reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  scan_id uuid,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 160),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, id),
  FOREIGN KEY (user_id, scan_id) REFERENCES public.scan_runs(user_id, id),
  CHECK (period_end >= period_start)
);
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
CREATE INDEX reports_user_time_idx ON public.reports(user_id, created_at DESC);

CREATE TABLE public.report_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  report_id uuid NOT NULL,
  position integer NOT NULL CHECK (position >= 0),
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 160),
  body text NOT NULL DEFAULT '' CHECK (char_length(body) <= 10000),
  UNIQUE (report_id, position),
  UNIQUE (user_id, report_id, id),
  FOREIGN KEY (user_id, report_id) REFERENCES public.reports(user_id, id) ON DELETE CASCADE
);
ALTER TABLE public.report_sections ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.report_charts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  report_id uuid NOT NULL,
  section_id uuid NOT NULL,
  chart_type text NOT NULL CHECK (chart_type IN ('BAR', 'LINE', 'DONUT')),
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 160),
  UNIQUE (user_id, id),
  FOREIGN KEY (user_id, report_id, section_id)
    REFERENCES public.report_sections(user_id, report_id, id) ON DELETE CASCADE
);
ALTER TABLE public.report_charts ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.report_chart_series (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  chart_id uuid NOT NULL,
  position integer NOT NULL CHECK (position >= 0),
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 100),
  unit text NOT NULL CHECK (char_length(unit) BETWEEN 1 AND 40),
  UNIQUE (chart_id, position),
  UNIQUE (user_id, id),
  FOREIGN KEY (user_id, chart_id) REFERENCES public.report_charts(user_id, id) ON DELETE CASCADE
);
ALTER TABLE public.report_chart_series ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.report_chart_points (
  user_id uuid NOT NULL,
  series_id uuid NOT NULL,
  position integer NOT NULL CHECK (position >= 0),
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 100),
  value numeric(20,4) NOT NULL CHECK (value >= 0 AND value <= 1000000000000000),
  PRIMARY KEY (user_id, series_id, position),
  FOREIGN KEY (user_id, series_id) REFERENCES public.report_chart_series(user_id, id) ON DELETE CASCADE
);
ALTER TABLE public.report_chart_points ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.report_exports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  report_id uuid NOT NULL,
  format_code text NOT NULL REFERENCES public.report_formats(code),
  status text NOT NULL DEFAULT 'REQUESTED' CHECK (status IN ('REQUESTED', 'READY', 'FAILED')),
  size_bytes bigint CHECK (size_bytes >= 0),
  sha256 text CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  FOREIGN KEY (user_id, report_id) REFERENCES public.reports(user_id, id) ON DELETE CASCADE,
  CHECK (completed_at IS NULL OR completed_at >= created_at),
  CHECK (status <> 'READY' OR (completed_at IS NOT NULL AND size_bytes IS NOT NULL AND sha256 IS NOT NULL))
);
ALTER TABLE public.report_exports ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.report_formats, public.reports, public.report_sections,
  public.report_charts, public.report_chart_series, public.report_chart_points,
  public.report_exports FROM PUBLIC, anon, authenticated;
COMMIT;
