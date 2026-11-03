BEGIN;

-- Anexo B aprobado: conservar las 30 tablas y añadir solo los caminos P0.
ALTER TABLE public.consent_purposes
  ADD COLUMN current_policy_version text NOT NULL DEFAULT '2026-10-26'
  CHECK (char_length(current_policy_version) BETWEEN 1 AND 40);

REVOKE UPDATE (changed_at) ON public.user_consents FROM authenticated;
REVOKE UPDATE (updated_at) ON public.user_preferences FROM authenticated;

CREATE FUNCTION public.touch_consent() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  current_version text;
BEGIN
  SELECT current_policy_version INTO current_version
    FROM public.consent_purposes WHERE code = NEW.purpose_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Finalidad de consentimiento inexistente' USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF NEW.granted THEN
    IF NEW.policy_version IS DISTINCT FROM current_version THEN
      RAISE EXCEPTION 'policy_version no vigente' USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    -- Retirar no exige aceptar el texto nuevo ni enviar policy_version.
    NEW.policy_version := CASE WHEN TG_OP = 'UPDATE' THEN OLD.policy_version ELSE current_version END;
  END IF;
  NEW.changed_at := now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER user_consents_touch BEFORE INSERT OR UPDATE ON public.user_consents
  FOR EACH ROW EXECUTE FUNCTION public.touch_consent();

CREATE FUNCTION public.touch_preferences() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER user_preferences_touch BEFORE INSERT OR UPDATE ON public.user_preferences
  FOR EACH ROW EXECUTE FUNCTION public.touch_preferences();

GRANT INSERT (user_id, asset_id) ON public.download_requests TO authenticated;
CREATE POLICY download_create ON public.download_requests FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id AND EXISTS (
    SELECT 1 FROM public.release_assets a JOIN public.app_releases r ON r.id = a.release_id
    WHERE a.id = download_requests.asset_id AND r.status = 'PUBLISHED'
  ));

GRANT UPDATE (revoked_at) ON public.devices TO authenticated;
CREATE POLICY device_revoke ON public.devices FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = user_id AND revoked_at IS NULL)
  WITH CHECK ((SELECT auth.uid()) = user_id AND revoked_at IS NOT NULL);

CREATE FUNCTION public.guard_device_revoke() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF OLD.revoked_at IS NOT NULL
     OR (to_jsonb(NEW) - 'revoked_at') IS DISTINCT FROM (to_jsonb(OLD) - 'revoked_at') THEN
    RAISE EXCEPTION 'Revocación irreversible; solo se puede cambiar revoked_at'
      USING ERRCODE = 'check_violation';
  END IF;
  -- Incluso un NULL o una fecha elegida por el cliente revoca con fecha del servidor.
  NEW.revoked_at := now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER devices_revoke_guard BEFORE UPDATE OF revoked_at ON public.devices
  FOR EACH ROW EXECUTE FUNCTION public.guard_device_revoke();

-- La RPC y el UPDATE directo atraviesan los mismos permisos, RLS y disparadores.
CREATE FUNCTION public.revoke_device(device_id uuid)
RETURNS TABLE (id uuid, revoked_at timestamptz)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
  UPDATE public.devices AS d SET revoked_at = now()
    WHERE d.id = $1 AND d.user_id = (SELECT auth.uid()) AND d.revoked_at IS NULL
    RETURNING d.id, d.revoked_at;
$$;
REVOKE ALL ON FUNCTION public.revoke_device(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_device(uuid) TO authenticated;

CREATE FUNCTION public.audit_write() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  expected_code text;
  expected_operation text;
  audited_device uuid;
BEGIN
  CASE TG_TABLE_NAME
    WHEN 'profiles' THEN expected_code := 'PROFILE_CREATED'; expected_operation := 'INSERT';
    WHEN 'user_consents' THEN expected_code := 'CONSENT_CHANGED'; expected_operation := TG_OP;
    WHEN 'download_requests' THEN expected_code := 'DOWNLOAD_REQUESTED'; expected_operation := 'INSERT';
    WHEN 'devices' THEN expected_code := 'DEVICE_REVOKED'; expected_operation := 'UPDATE';
    ELSE RAISE EXCEPTION 'Contexto de auditoría no permitido' USING ERRCODE = 'insufficient_privilege';
  END CASE;
  IF TG_TABLE_SCHEMA <> 'public' OR TG_NARGS <> 1
     OR TG_ARGV[0] IS DISTINCT FROM expected_code OR TG_OP <> expected_operation
     OR TG_OP NOT IN ('INSERT', 'UPDATE') THEN
    RAISE EXCEPTION 'Contexto de auditoría no permitido' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF TG_TABLE_NAME = 'devices' THEN
    audited_device := NEW.id;
    INSERT INTO public.device_events(user_id, device_id, event_code, app_version, occurred_at)
      VALUES (NEW.user_id, NEW.id, 'REVOKED', NEW.app_version, NEW.revoked_at);
  END IF;
  INSERT INTO public.audit_events(user_id, event_code, device_id)
    VALUES (NEW.user_id, expected_code, audited_device);
  RETURN NEW;
END;
$$;

-- Evita la ejecución directa/RPC. Solo los triggers instalados por la migración
-- pueden escribir auditoría; el dueño de la función es el rol de migración.
REVOKE ALL ON FUNCTION public.audit_write() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.touch_consent() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.touch_preferences() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_device_revoke() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER audit_download AFTER INSERT ON public.download_requests
  FOR EACH ROW EXECUTE FUNCTION public.audit_write('DOWNLOAD_REQUESTED');
CREATE TRIGGER audit_consent AFTER INSERT OR UPDATE ON public.user_consents
  FOR EACH ROW EXECUTE FUNCTION public.audit_write('CONSENT_CHANGED');
CREATE TRIGGER audit_profile AFTER INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.audit_write('PROFILE_CREATED');
CREATE TRIGGER audit_revoke AFTER UPDATE OF revoked_at ON public.devices
  FOR EACH ROW EXECUTE FUNCTION public.audit_write('DEVICE_REVOKED');

COMMIT;
