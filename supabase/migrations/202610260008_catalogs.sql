BEGIN;
INSERT INTO public.consent_purposes(code, description) VALUES
  ('scan_summaries', 'Compartir contadores de análisis sin rutas ni archivos.'),
  ('report_storage', 'Guardar reportes revisados y anonimizados en la cuenta.');
INSERT INTO public.device_platforms(code, label) VALUES ('windows-x64', 'Windows 10/11 x64');
INSERT INTO public.scan_statuses(code, label) VALUES
  ('CREATED', 'Creado'), ('DISCOVERING', 'Descubriendo'), ('SCANNING', 'Analizando'),
  ('CANCELLING', 'Cancelando'), ('CANCELLED', 'Cancelado'), ('COMPLETED', 'Completado'), ('FAILED', 'Fallido');
INSERT INTO public.verdict_types(code, label) VALUES
  ('NOT_EVALUATED', 'Sin evaluar'), ('CLEAN', 'Limpio'), ('SUSPICIOUS', 'Sospechoso'),
  ('DETECTED', 'Detectado'), ('NOT_ANALYZED', 'No analizado');
INSERT INTO public.scan_zones(code, label) VALUES
  ('DESCARGAS', 'Descargas'), ('ESCRITORIO', 'Escritorio'), ('DOCUMENTOS', 'Documentos'),
  ('TEMPORALES', 'Temporales'), ('DATOS_APPS', 'Datos de aplicaciones'),
  ('EXTRAIBLE', 'Unidad extraíble'), ('PROGRAMAS', 'Programas'), ('SISTEMA', 'Sistema'), ('OTRA', 'Otra');
INSERT INTO public.detection_layers(code, label) VALUES
  ('HASH', 'Hash'), ('SIGNATURES', 'Firmas'), ('FILETYPE', 'Tipo de archivo'),
  ('RULES', 'Reglas'), ('SCRIPTS', 'Scripts'), ('HEURISTICS', 'Heurísticas'), ('PE', 'Ejecutables PE');
INSERT INTO public.report_formats(code, mime_type, extension) VALUES
  ('html', 'text/html', 'html'), ('csv', 'text/csv', 'csv'), ('json', 'application/json', 'json');
INSERT INTO public.audit_event_types(code, description) VALUES
  ('PROFILE_CREATED', 'Perfil creado'), ('CONSENT_CHANGED', 'Consentimiento cambiado'),
  ('DEVICE_LINKED', 'Equipo vinculado'), ('DEVICE_REVOKED', 'Equipo revocado'),
  ('DOWNLOAD_REQUESTED', 'Descarga solicitada'), ('SUMMARY_RECEIVED', 'Resumen recibido'),
  ('REPORT_STORED', 'Reporte almacenado');
COMMIT;
