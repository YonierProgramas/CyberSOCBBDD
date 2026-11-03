-- Solo para una BD descartable PostgreSQL vacía. Nunca aplicar en Supabase remoto.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  -- Doble de Auth, no proveedor real: admite SET LOCAL de las pruebas SQL y
  -- request.jwt.claims que establece PostgREST tras verificar un JWT de prueba.
  SELECT coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid;
$$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;
