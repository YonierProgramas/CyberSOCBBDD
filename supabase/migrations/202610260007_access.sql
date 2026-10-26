BEGIN;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Primero lectura por propietario. Publicar, vincular, sincronizar y auditar
-- requerirán operaciones de servidor revisadas; no se concede escritura general.
DO $policies$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'profiles', 'user_preferences', 'user_consents', 'devices', 'device_settings',
    'device_events', 'download_requests', 'scan_runs', 'scan_verdict_totals',
    'scan_zone_totals', 'scan_layer_totals', 'reports', 'report_sections',
    'report_charts', 'report_chart_series', 'report_chart_points', 'report_exports',
    'audit_events'
  ] LOOP
    EXECUTE format('GRANT SELECT ON public.%I TO authenticated', table_name);
    EXECUTE format('GRANT ALL PRIVILEGES ON public.%I TO service_role', table_name);
    EXECUTE format(
      'CREATE POLICY owner_read ON public.%I FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id)',
      table_name
    );
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'consent_purposes', 'device_platforms', 'scan_statuses', 'verdict_types',
    'scan_zones', 'detection_layers', 'report_formats', 'audit_event_types'
  ] LOOP
    EXECUTE format('GRANT SELECT ON public.%I TO authenticated', table_name);
    EXECUTE format('GRANT ALL PRIVILEGES ON public.%I TO service_role', table_name);
    EXECUTE format('CREATE POLICY catalog_read ON public.%I FOR SELECT TO authenticated USING (true)', table_name);
  END LOOP;
END
$policies$;

-- El proveedor valida la identidad; esto solo permite crear el perfil propio.
GRANT INSERT ON public.profiles TO authenticated;
GRANT UPDATE (display_name) ON public.profiles TO authenticated;
CREATE POLICY profile_create ON public.profiles FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY profile_update ON public.profiles FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id);

GRANT INSERT ON public.user_preferences, public.user_consents TO authenticated;
GRANT UPDATE (locale, timezone, theme, updated_at) ON public.user_preferences TO authenticated;
GRANT UPDATE (granted, policy_version, changed_at) ON public.user_consents TO authenticated;
CREATE POLICY preferences_create ON public.user_preferences FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY preferences_update ON public.user_preferences FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY consent_create ON public.user_consents FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY consent_update ON public.user_consents FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id);

GRANT SELECT ON public.app_releases, public.release_assets, public.release_notes TO anon, authenticated;
CREATE POLICY release_read ON public.app_releases FOR SELECT TO anon, authenticated
  USING (status = 'PUBLISHED');
CREATE POLICY asset_read ON public.release_assets FOR SELECT TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM public.app_releases r WHERE r.id = release_id AND r.status = 'PUBLISHED'));
CREATE POLICY notes_read ON public.release_notes FOR SELECT TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM public.app_releases r WHERE r.id = release_id AND r.status = 'PUBLISHED'));

-- Rol del servicio: solo desde una API autorizada; nunca distribuirlo en clientes.
GRANT ALL PRIVILEGES ON public.app_releases, public.release_assets,
  public.release_notes, public.device_links TO service_role;

-- device_links no tiene política ni permiso para anon/authenticated: denegado.
COMMIT;
