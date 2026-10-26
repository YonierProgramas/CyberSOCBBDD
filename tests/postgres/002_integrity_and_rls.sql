BEGIN;
-- IDs y nombres ficticios, exclusivamente en la BD descartable del comprobador.
INSERT INTO auth.users(id) VALUES
 ('10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002'),
 ('20000000-0000-0000-0000-000000000003');
INSERT INTO public.profiles(user_id, display_name) VALUES
 ('10000000-0000-0000-0000-000000000001', 'Demo A'),
 ('20000000-0000-0000-0000-000000000002', 'Demo B');
INSERT INTO public.user_preferences(user_id)
 SELECT user_id FROM public.profiles;
INSERT INTO public.user_consents(user_id, purpose_code, granted, policy_version)
 SELECT p.user_id, c.code, true, 'demo-v1' FROM public.profiles p CROSS JOIN public.consent_purposes c;

INSERT INTO public.devices(id, user_id, installation_id, platform_code, display_name, app_version) VALUES
 ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001', 'windows-x64', 'Equipo Demo A', '0.1.0'),
 ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002',
  '40000000-0000-0000-0000-000000000002', 'windows-x64', 'Equipo Demo B', '0.1.0');
INSERT INTO public.device_settings(user_id, device_id)
 SELECT user_id, id FROM public.devices;
INSERT INTO public.device_events(user_id, device_id, event_code)
 SELECT user_id, id, 'LINKED' FROM public.devices;
INSERT INTO public.device_links(user_id, code_hash, expires_at) VALUES
 ('10000000-0000-0000-0000-000000000001', repeat('0',64), now() + interval '5 minutes');

INSERT INTO public.app_releases(id, version, source_commit, status, published_at) VALUES
 ('50000000-0000-0000-0000-000000000001', '0.1.0', repeat('0',40), 'PUBLISHED', now()),
 ('50000000-0000-0000-0000-000000000002', '0.2.0', repeat('0',40), 'DRAFT', NULL);
INSERT INTO public.release_assets(id, release_id, platform_code, download_url, sha256, size_bytes) VALUES
 ('60000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001',
  'windows-x64', 'https://example.invalid/demo-a.exe', repeat('0',64), 100),
 ('60000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000002',
  'windows-x64', 'https://example.invalid/demo-b.exe', repeat('0',64), 100);
INSERT INTO public.release_notes(release_id, locale, body)
 SELECT id, 'es', 'Nota ficticia de prueba' FROM public.app_releases;
INSERT INTO public.download_requests(user_id, asset_id) VALUES
 ('10000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001');

INSERT INTO public.scan_runs(id, user_id, device_id, local_scan_id, status_code,
 files_discovered, files_processed, files_error, files_skipped, started_at, finished_at) VALUES
 ('70000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001',
  'COMPLETED', 10, 10, 0, 0, now(), now()),
 ('70000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002',
  '30000000-0000-0000-0000-000000000002', '80000000-0000-0000-0000-000000000002',
  'COMPLETED', 10, 10, 0, 0, now(), now());
INSERT INTO public.scan_verdict_totals(user_id, scan_id, verdict_code, file_count)
 SELECT user_id, id, 'CLEAN', 10 FROM public.scan_runs;
INSERT INTO public.scan_zone_totals(user_id, scan_id, zone_code, file_count)
 SELECT user_id, id, 'DESCARGAS', 10 FROM public.scan_runs;
INSERT INTO public.scan_layer_totals(user_id, scan_id, layer_code, executions, hits, errors)
 SELECT user_id, id, 'SIGNATURES', 10, 0, 0 FROM public.scan_runs;

INSERT INTO public.reports(id, user_id, scan_id, title, period_start, period_end) VALUES
 ('90000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000001', 'Resumen ficticio', now(), now());
INSERT INTO public.report_sections(id, user_id, report_id, position, title) VALUES
 ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
  '90000000-0000-0000-0000-000000000001', 0, 'Distribución');
INSERT INTO public.report_charts(id, user_id, report_id, section_id, chart_type, title) VALUES
 ('b0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
  '90000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'BAR', 'Veredictos');
INSERT INTO public.report_chart_series(id, user_id, chart_id, position, label, unit) VALUES
 ('c0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-000000000001', 0, 'Archivos', 'cantidad');
INSERT INTO public.report_chart_points(user_id, series_id, position, label, value) VALUES
 ('10000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 0, 'Limpios', 10);
INSERT INTO public.report_exports(user_id, report_id, format_code) VALUES
 ('10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'json');
INSERT INTO public.audit_events(user_id, event_code, device_id)
 SELECT user_id, 'DEVICE_LINKED', id FROM public.devices;

DO $test$
DECLARE table_name text; row_count bigint;
BEGIN
  FOR table_name IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', table_name) INTO row_count;
    IF row_count = 0 THEN RAISE EXCEPTION 'El recorrido no ejercita la tabla %.', table_name; END IF;
  END LOOP;
  BEGIN
    INSERT INTO public.scan_runs(user_id, device_id, local_scan_id, status_code,
      files_discovered, files_processed, files_error, files_skipped, started_at)
    VALUES ('20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001',
      gen_random_uuid(), 'COMPLETED', 1, 1, 0, 0, now());
    RAISE EXCEPTION 'Se aceptó un resumen para equipo de otra cuenta.';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.scan_verdict_totals(user_id, scan_id, verdict_code, file_count)
    VALUES ('10000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 'DETECTED', -1);
    RAISE EXCEPTION 'Se aceptó contador negativo.';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.scan_runs(user_id, device_id, local_scan_id, status_code,
      files_discovered, files_processed, files_error, files_skipped, started_at)
    SELECT user_id, device_id, local_scan_id, status_code, files_discovered, files_processed,
      files_error, files_skipped, started_at FROM public.scan_runs LIMIT 1;
    RAISE EXCEPTION 'Reintentar creó un segundo resumen.';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.report_chart_points(user_id, series_id, position, label, value)
    VALUES ('20000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 1, 'Otro', 5);
    RAISE EXCEPTION 'Se mezclaron propietarios en una serie.';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END
$test$;
SELECT 'PASS: recorrido de seis módulos y restricciones de integridad' AS resultado;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '20000000-0000-0000-0000-000000000002';
DO $test$
DECLARE table_name text; foreign_count bigint; changed integer;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'profiles', 'user_preferences', 'user_consents', 'devices', 'device_settings',
    'device_events', 'download_requests', 'scan_runs', 'scan_verdict_totals',
    'scan_zone_totals', 'scan_layer_totals', 'reports', 'report_sections', 'report_charts',
    'report_chart_series', 'report_chart_points', 'report_exports', 'audit_events'
  ] LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE user_id <> auth.uid()', table_name) INTO foreign_count;
    IF foreign_count <> 0 THEN RAISE EXCEPTION 'Fuga de filas ajenas en %.', table_name; END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.scan_runs) <> 1 THEN RAISE EXCEPTION 'El usuario B no ve su análisis.'; END IF;
  IF (SELECT count(*) FROM public.reports) <> 0 THEN RAISE EXCEPTION 'B puede leer el reporte de A.'; END IF;
  UPDATE public.profiles SET display_name = 'Intento ajeno'
    WHERE user_id = '10000000-0000-0000-0000-000000000001';
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 0 THEN RAISE EXCEPTION 'B puede cambiar perfil de A.'; END IF;
  BEGIN
    INSERT INTO public.profiles(user_id, display_name)
    VALUES ('20000000-0000-0000-0000-000000000003', 'Intento ajeno');
    RAISE EXCEPTION 'B puede crear perfil para otra identidad.';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM * FROM public.device_links;
    RAISE EXCEPTION 'El cliente puede leer hashes de vinculación.';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE public.app_releases SET status = 'PUBLISHED', published_at = now();
    RAISE EXCEPTION 'Un usuario puede publicar versiones.';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.audit_events(user_id, event_code) VALUES (auth.uid(), 'PROFILE_CREATED');
    RAISE EXCEPTION 'Un cliente puede fabricar auditoría.';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  UPDATE public.user_consents SET granted = false WHERE user_id = auth.uid();
END
$test$;
SELECT 'PASS: B solo lee sus datos, no modifica A ni publica/audita' AS resultado;

SET LOCAL request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
DO $test$
BEGIN
  IF (SELECT value FROM public.report_chart_points) <> 10 THEN RAISE EXCEPTION 'A perdió su gráfico.'; END IF;
  IF EXISTS (SELECT 1 FROM public.user_consents WHERE NOT granted) THEN RAISE EXCEPTION 'B cambió el consentimiento de A.'; END IF;
END
$test$;

SET LOCAL ROLE anon;
SET LOCAL request.jwt.claim.sub = '';
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.app_releases) <> 1 THEN RAISE EXCEPTION 'El anónimo ve borradores.'; END IF;
  IF (SELECT count(*) FROM public.release_assets) <> 1 THEN RAISE EXCEPTION 'El anónimo ve binarios no publicados.'; END IF;
  IF (SELECT count(*) FROM public.release_notes) <> 1 THEN RAISE EXCEPTION 'El anónimo ve notas no publicadas.'; END IF;
  BEGIN
    PERFORM * FROM public.profiles;
    RAISE EXCEPTION 'El anónimo accede a perfiles.';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END
$test$;
SELECT 'PASS: acceso público solo a versiones publicadas, sin perfiles' AS resultado;
ROLLBACK;
