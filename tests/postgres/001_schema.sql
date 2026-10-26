BEGIN;
DO $test$
DECLARE table_count integer; secured_count integer; table_name text;
BEGIN
  SELECT count(*) INTO table_count FROM pg_tables WHERE schemaname = 'public';
  IF table_count <> 30 THEN RAISE EXCEPTION 'Se esperaban 30 tablas propias; hay %.', table_count; END IF;
  SELECT count(*) INTO secured_count FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity;
  IF secured_count <> 30 THEN RAISE EXCEPTION 'RLS no está habilitado en las 30 tablas.'; END IF;
  FOR table_name IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    IF has_table_privilege('authenticated', format('public.%I', table_name), 'TRUNCATE') THEN
      RAISE EXCEPTION 'Un cliente puede truncar %.', table_name;
    END IF;
  END LOOP;
  IF has_table_privilege('authenticated', 'public.device_links', 'SELECT') THEN
    RAISE EXCEPTION 'Los clientes no deben leer solicitudes de vinculación.';
  END IF;
  IF has_table_privilege('anon', 'public.profiles', 'SELECT') THEN
    RAISE EXCEPTION 'Acceso anónimo a perfiles.';
  END IF;
END
$test$;
SELECT 'PASS: 30 tablas propias, RLS y privilegios mínimos' AS resultado;
ROLLBACK;
