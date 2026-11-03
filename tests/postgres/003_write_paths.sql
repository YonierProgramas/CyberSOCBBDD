BEGIN;
-- Todos los datos son ficticios y se revierten; no corresponde a Supabase remoto.
INSERT INTO auth.users(id) VALUES
 ('10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002');
INSERT INTO public.profiles(user_id, display_name) VALUES
 ('10000000-0000-0000-0000-000000000001', 'SQL ficticio A'),
 ('20000000-0000-0000-0000-000000000002', 'SQL ficticio B');
INSERT INTO public.user_preferences(user_id, updated_at)
 SELECT user_id, '2000-01-01' FROM public.profiles;
INSERT INTO public.user_consents(user_id, purpose_code, granted, policy_version, changed_at)
 SELECT user_id, 'scan_summaries', true, '2026-10-26', '2000-01-01' FROM public.profiles;
INSERT INTO public.devices(id, user_id, installation_id, platform_code, display_name, app_version) VALUES
 ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001', 'windows-x64', 'Ficticio A1', '0.1.0'),
 ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002',
  '40000000-0000-0000-0000-000000000002', 'windows-x64', 'Ficticio B', '0.1.0'),
 ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000003', 'windows-x64', 'Ficticio A2', '0.1.0');
INSERT INTO public.app_releases(id, version, source_commit, status, published_at) VALUES
 ('50000000-0000-0000-0000-000000000001', '0.1.0', repeat('0',40), 'PUBLISHED', now()),
 ('50000000-0000-0000-0000-000000000002', '0.2.0', repeat('0',40), 'DRAFT', NULL),
 ('50000000-0000-0000-0000-000000000003', '0.3.0', repeat('0',40), 'REVOKED', now());
INSERT INTO public.release_assets(id, release_id, platform_code, download_url, sha256, size_bytes)
 SELECT ('60000000-0000-0000-0000-' || right(id::text, 12))::uuid, id, 'windows-x64',
   'https://example.invalid/fixture.exe', repeat('0',64), 100 FROM public.app_releases;

DO $test$
DECLARE function_name text;
BEGIN
  IF has_column_privilege('authenticated', 'public.user_consents', 'changed_at', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.user_preferences', 'updated_at', 'UPDATE') THEN
    RAISE EXCEPTION 'El cliente conserva permisos de modificar fechas';
  END IF;
  FOREACH function_name IN ARRAY ARRAY['audit_write()', 'touch_consent()', 'touch_preferences()', 'guard_device_revoke()'] LOOP
    IF has_function_privilege('authenticated', 'public.' || function_name, 'EXECUTE')
       OR has_function_privilege('anon', 'public.' || function_name, 'EXECUTE') THEN
      RAISE EXCEPTION 'Función de trigger expuesta: %', function_name;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='audit_write' AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Auditoría sin SECURITY DEFINER/search_path fijo';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='revoke_device' AND p.prosecdef) THEN
    RAISE EXCEPTION 'RPC de revocación elevada';
  END IF;
  IF (SELECT count(*) FROM public.audit_events WHERE event_code='PROFILE_CREATED') <> 2 THEN
    RAISE EXCEPTION 'No se auditó la creación de ambos perfiles';
  END IF;
END
$test$;
SELECT 'PASS B-04/B-05: permisos mínimos, funciones cerradas y fechas de servidor' AS resultado;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
DO $test$
DECLARE changed integer; result_count integer;
BEGIN
  IF (SELECT changed_at FROM public.user_consents) <> now()
     OR (SELECT updated_at FROM public.user_preferences) <> now() THEN
    RAISE EXCEPTION 'Se aceptó fecha falsa al insertar';
  END IF;
  UPDATE public.profiles SET display_name='Cruce' WHERE user_id <> auth.uid();
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 0 THEN RAISE EXCEPTION 'Cambio de perfil ajeno'; END IF;
  UPDATE public.user_preferences SET theme='dark' WHERE user_id <> auth.uid();
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 0 THEN RAISE EXCEPTION 'Cambio de preferencias ajenas'; END IF;
  UPDATE public.user_consents SET granted=false WHERE user_id <> auth.uid();
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 0 THEN RAISE EXCEPTION 'Cambio de consentimiento ajeno'; END IF;
  UPDATE public.devices SET revoked_at=now() WHERE user_id <> auth.uid();
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 0 THEN RAISE EXCEPTION 'Revocación ajena'; END IF;
  SELECT count(*) INTO result_count FROM public.revoke_device('30000000-0000-0000-0000-000000000002');
  IF result_count <> 0 THEN RAISE EXCEPTION 'RPC revocó equipo ajeno'; END IF;
  SELECT count(*) INTO result_count FROM public.revoke_device('ffffffff-ffff-ffff-ffff-ffffffffffff');
  IF result_count <> 0 THEN RAISE EXCEPTION 'RPC inventó equipo inexistente'; END IF;
  BEGIN
    INSERT INTO public.download_requests(user_id,asset_id)
      VALUES ('20000000-0000-0000-0000-000000000002','60000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'Descarga con dueño B aceptada';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.download_requests(user_id,asset_id)
      VALUES (auth.uid(),'60000000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'Descarga DRAFT aceptada';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.download_requests(user_id,asset_id)
      VALUES (auth.uid(),'60000000-0000-0000-0000-000000000003');
    RAISE EXCEPTION 'Descarga REVOKED aceptada';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.download_requests(user_id,asset_id,requested_at)
      VALUES (auth.uid(),'60000000-0000-0000-0000-000000000001','2000-01-01');
    RAISE EXCEPTION 'Fecha de descarga controlada por cliente';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO public.download_requests(user_id,asset_id)
    VALUES (auth.uid(),'60000000-0000-0000-0000-000000000001');
  IF (SELECT count(*) FROM public.audit_events WHERE event_code='DOWNLOAD_REQUESTED') <> 1 THEN
    RAISE EXCEPTION 'Descarga no auditada exactamente una vez';
  END IF;
  BEGIN
    INSERT INTO public.audit_events(user_id,event_code) VALUES (auth.uid(),'PROFILE_CREATED');
    RAISE EXCEPTION 'Auditoría falsificada';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.device_events(user_id,device_id,event_code)
      VALUES (auth.uid(),'30000000-0000-0000-0000-000000000001','REVOKED');
    RAISE EXCEPTION 'Evento falsificado';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.audit_write();
    RAISE EXCEPTION 'Función de auditoría expuesta directamente';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE public.user_consents SET changed_at='2099-01-01' WHERE user_id=auth.uid();
    RAISE EXCEPTION 'UPDATE de fecha de consentimiento permitido';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE public.user_preferences SET updated_at='2099-01-01' WHERE user_id=auth.uid();
    RAISE EXCEPTION 'UPDATE de fecha de preferencias permitido';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  UPDATE public.user_preferences SET theme='dark' WHERE user_id=auth.uid();
  UPDATE public.devices SET revoked_at='2099-01-01' WHERE id='30000000-0000-0000-0000-000000000001';
  IF (SELECT revoked_at FROM public.devices WHERE id='30000000-0000-0000-0000-000000000001') <> now() THEN
    RAISE EXCEPTION 'Revocación no usa fecha de servidor';
  END IF;
  UPDATE public.devices SET revoked_at=NULL WHERE id='30000000-0000-0000-0000-000000000001';
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 0 THEN RAISE EXCEPTION 'Se reactivó equipo revocado'; END IF;
  SELECT count(*) INTO result_count FROM public.revoke_device('30000000-0000-0000-0000-000000000003');
  IF result_count <> 1 THEN RAISE EXCEPTION 'RPC propia no revocó'; END IF;
  SELECT count(*) INTO result_count FROM public.revoke_device('30000000-0000-0000-0000-000000000003');
  IF result_count <> 0 THEN RAISE EXCEPTION 'RPC repetida no es vacía'; END IF;
  IF (SELECT count(*) FROM public.device_events WHERE event_code='REVOKED') <> 2
     OR (SELECT count(*) FROM public.audit_events WHERE event_code='DEVICE_REVOKED') <> 2 THEN
    RAISE EXCEPTION 'Revocaciones/eventos/auditoría no coinciden';
  END IF;
  BEGIN
    UPDATE public.devices SET display_name='Otro', revoked_at=now() WHERE id='30000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'Cambio de otra columna del equipo';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END
$test$;
SELECT 'PASS B-01/B-02/B-03/B-04: dueño A, descargas, RPC/UPDATE y eventos inalterables' AS resultado;

RESET ROLE;
UPDATE public.consent_purposes SET current_policy_version='v2' WHERE code='scan_summaries';
SET LOCAL ROLE authenticated;
DO $test$
BEGIN
  IF EXISTS (SELECT 1 FROM public.user_consents c JOIN public.consent_purposes p ON p.code=c.purpose_code
    WHERE c.granted AND c.policy_version=p.current_policy_version) THEN
    RAISE EXCEPTION 'Consentimiento anterior sigue siendo efectivo';
  END IF;
  UPDATE public.user_consents SET granted=false, policy_version='v2-no-aceptada' WHERE user_id=auth.uid();
  IF (SELECT policy_version FROM public.user_consents WHERE purpose_code='scan_summaries') <> '2026-10-26'
     OR (SELECT granted FROM public.user_consents WHERE purpose_code='scan_summaries') THEN
    RAISE EXCEPTION 'Retirar obligó a aceptar una versión nueva';
  END IF;
  UPDATE public.user_consents SET granted=false, policy_version=NULL WHERE user_id=auth.uid();
  BEGIN
    UPDATE public.user_consents SET granted=true, policy_version='2026-10-26' WHERE user_id=auth.uid();
    RAISE EXCEPTION 'Se concedió una versión anterior';
  EXCEPTION WHEN check_violation THEN NULL; END;
  UPDATE public.user_consents SET granted=true, policy_version='v2' WHERE user_id=auth.uid();
  UPDATE public.user_consents SET granted=false WHERE user_id=auth.uid();
  IF (SELECT policy_version FROM public.user_consents WHERE purpose_code='scan_summaries') <> 'v2'
     OR (SELECT changed_at FROM public.user_consents WHERE purpose_code='scan_summaries') <> now() THEN
    RAISE EXCEPTION 'Retirada sin versión o fecha de servidor incorrecta';
  END IF;
  INSERT INTO public.user_consents(user_id,purpose_code,granted,changed_at)
    VALUES (auth.uid(),'report_storage',false,'2099-01-01');
  IF (SELECT policy_version FROM public.user_consents WHERE purpose_code='report_storage') <> '2026-10-26'
     OR (SELECT changed_at FROM public.user_consents WHERE purpose_code='report_storage') <> now() THEN
    RAISE EXCEPTION 'Primera decisión false sin versión no normalizada';
  END IF;
  BEGIN
    INSERT INTO public.user_consents(user_id,purpose_code,granted,policy_version)
      VALUES ('20000000-0000-0000-0000-000000000002','report_storage',true,'2026-10-26');
    RAISE EXCEPTION 'Consentimiento insertado para B';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END
$test$;
SELECT 'PASS B-05/B-09: versión vigente, retirada v1 tras v2, fecha servidor y primera retirada' AS resultado;

SET LOCAL request.jwt.claim.sub='20000000-0000-0000-0000-000000000002';
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.devices WHERE revoked_at IS NOT NULL) <> 0
     OR (SELECT count(*) FROM public.download_requests) <> 0 THEN
    RAISE EXCEPTION 'B observa efectos de A';
  END IF;
  UPDATE public.user_consents SET granted=false WHERE user_id=auth.uid();
  IF (SELECT policy_version FROM public.user_consents) <> '2026-10-26' THEN
    RAISE EXCEPTION 'Retirada B alteró versión anterior';
  END IF;
END
$test$;

RESET ROLE;
DO $test$
DECLARE previous_count integer;
BEGIN
  SELECT count(*) INTO previous_count FROM public.audit_events;
  BEGIN
    INSERT INTO public.profiles(user_id,display_name)
      VALUES ('ffffffff-ffff-ffff-ffff-ffffffffffff','Sin usuario');
    RAISE EXCEPTION 'Se creó perfil sin auth.users';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
  IF (SELECT count(*) FROM public.audit_events) <> previous_count THEN
    RAISE EXCEPTION 'Una escritura fallida dejó auditoría suelta';
  END IF;
  -- Borrado manual autorizado de cuenta: cascadas, no función nueva de borrado.
  DELETE FROM auth.users WHERE id='10000000-0000-0000-0000-000000000001';
  IF EXISTS (SELECT 1 FROM public.profiles WHERE user_id='10000000-0000-0000-0000-000000000001')
     OR EXISTS (SELECT 1 FROM public.audit_events WHERE user_id='10000000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'Cascada de cuenta deja perfil/auditoría';
  END IF;
END
$test$;
SELECT 'PASS B6: auditoría atómica y borrado manual en cascada' AS resultado;
ROLLBACK;
