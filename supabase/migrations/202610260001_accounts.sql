BEGIN;

CREATE TABLE public.profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 100),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.user_preferences (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  locale text NOT NULL DEFAULT 'es-CO' CHECK (locale IN ('es-CO', 'es')),
  timezone text NOT NULL DEFAULT 'America/Bogota' CHECK (char_length(timezone) BETWEEN 1 AND 100),
  theme text NOT NULL DEFAULT 'system' CHECK (theme IN ('system', 'light', 'dark')),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.consent_purposes (
  code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z_]{1,49}$'),
  description text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 300)
);
ALTER TABLE public.consent_purposes ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.user_consents (
  user_id uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  purpose_code text NOT NULL REFERENCES public.consent_purposes(code),
  granted boolean NOT NULL DEFAULT false,
  policy_version text NOT NULL CHECK (char_length(policy_version) BETWEEN 1 AND 40),
  changed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, purpose_code)
);
ALTER TABLE public.user_consents ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.profiles, public.user_preferences, public.consent_purposes,
  public.user_consents FROM PUBLIC, anon, authenticated;
COMMIT;
