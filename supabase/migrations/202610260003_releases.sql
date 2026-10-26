BEGIN;

CREATE TABLE public.app_releases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version text NOT NULL UNIQUE CHECK (version ~ '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$'),
  source_commit text NOT NULL CHECK (source_commit ~ '^[0-9a-f]{40}$'),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PUBLISHED', 'REVOKED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  CHECK (status <> 'PUBLISHED' OR published_at IS NOT NULL)
);
ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.release_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  release_id uuid NOT NULL REFERENCES public.app_releases(id) ON DELETE CASCADE,
  platform_code text NOT NULL REFERENCES public.device_platforms(code),
  download_url text NOT NULL CHECK (download_url ~ '^https://[^[:space:]]+$' AND char_length(download_url) <= 2048),
  sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes < 2147483648),
  UNIQUE (release_id, platform_code)
);
ALTER TABLE public.release_assets ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.release_notes (
  release_id uuid NOT NULL REFERENCES public.app_releases(id) ON DELETE CASCADE,
  locale text NOT NULL CHECK (locale IN ('es', 'es-CO')),
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 10000),
  PRIMARY KEY (release_id, locale)
);
ALTER TABLE public.release_notes ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.download_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES public.release_assets(id),
  requested_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.download_requests ENABLE ROW LEVEL SECURITY;
CREATE INDEX download_requests_user_time_idx ON public.download_requests(user_id, requested_at DESC);

REVOKE ALL ON public.app_releases, public.release_assets, public.release_notes,
  public.download_requests FROM PUBLIC, anon, authenticated;
COMMIT;
