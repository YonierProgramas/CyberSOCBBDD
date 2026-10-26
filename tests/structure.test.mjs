import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const expected = JSON.parse(readFileSync(resolve(root, 'tests/expected-tables.json'), 'utf8'));
const names = readdirSync(resolve(root, 'supabase/migrations')).sort();
const migrations = names.map(name => readFileSync(resolve(root, 'supabase/migrations', name), 'utf8'));
const sql = migrations.join('\n');

test('el esquema contiene exactamente las 30 tablas propias esperadas', () => {
  const actual = [...sql.matchAll(/CREATE TABLE public\.([a-z_]+)\s*\(/g)].map(match => match[1]);
  assert.equal(expected.length, 30);
  assert.deepEqual(actual.toSorted(), expected.toSorted());
});

test('cada tabla se crea con RLS y cada migración es transaccional', () => {
  for (const name of expected) {
    assert.ok(sql.includes(`ALTER TABLE public.${name} ENABLE ROW LEVEL SECURITY;`), name);
  }
  for (const migration of migrations) {
    assert.match(migration, /^BEGIN;/);
    assert.match(migration.trimEnd(), /COMMIT;$/);
  }
});

test('el vínculo de equipo no concede permisos de cliente y no almacena códigos en claro', () => {
  const devices = migrations[1];
  const links = devices.slice(devices.indexOf('CREATE TABLE public.device_links'));
  assert.match(links, /code_hash text NOT NULL UNIQUE/);
  assert.doesNotMatch(links, /\b(code|access_token|refresh_token|password)\s+(text|varchar)/i);
  assert.doesNotMatch(migrations[6], /GRANT[^;]*device_links[^;]*TO (?:anon|authenticated)/i);
});

test('resúmenes no duplican archivos y los detalles mantienen propietario en FK compuesta', () => {
  const scans = migrations[3];
  assert.doesNotMatch(scans, /\b(path|file_name|content|message)\s+text/i);
  assert.match(scans, /UNIQUE \(device_id, local_scan_id\)/);
  for (const name of ['scan_verdict_totals', 'scan_zone_totals', 'scan_layer_totals']) {
    const body = scans.slice(scans.indexOf(`CREATE TABLE public.${name}`));
    assert.match(body.slice(0, body.indexOf(');')), /FOREIGN KEY \(user_id, scan_id\)/);
  }
});

test('no hay datos reales de cuenta ni borrado de bases en migraciones', () => {
  assert.doesNotMatch(sql, /INSERT INTO auth\.users|DROP DATABASE|DROP SCHEMA|TRUNCATE/i);
  assert.doesNotMatch(sql, /sk-ant-|ghp_|gho_|postgres(?:ql)?:\/\//);
});

test('el inventario no usa tablas del proveedor o migraciones para inflar el conteo', () => {
  assert.ok(expected.every(name => /^[a-z_]+$/.test(name)));
  assert.ok(expected.every(name => !['users', 'schema_migrations', 'objects', 'buckets'].includes(name)));
});
