import assert from 'node:assert/strict';
import test from 'node:test';
import { spawnSync } from 'node:child_process';
import { generateKeyPairSync, randomInt, randomUUID, sign } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import { waitForPostgres } from '../scripts/test-postgres.mjs';

// Herramientas de prueba oficiales fijadas por digest, no dependencias de la API.
const postgresImage = 'postgres@sha256:266d3c257594e195b309ae9d1805e54c788f1d7b375f56bf6c367aac6c917e7b';
const postgrestImage = 'postgrest/postgrest@sha256:1347d7552b88f17832912c06afbf7c43209af6eeeb60834b04aae12c9bd9d5cc';
const A = '10000000-0000-0000-0000-000000000001';
const B = '20000000-0000-0000-0000-000000000002';
const deviceA = '30000000-0000-0000-0000-000000000001';
const deviceB = '30000000-0000-0000-0000-000000000002';
const deviceConcurrent = '30000000-0000-0000-0000-000000000003';
const publishedAsset = '60000000-0000-0000-0000-000000000001';
const draftAsset = '60000000-0000-0000-0000-000000000002';

function docker(args, input, allowFailure = false, timeout = 15000) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', windowsHide: true,
    timeout, killSignal: 'SIGKILL', maxBuffer: 4 * 1024 * 1024 });
  if (!allowFailure && (result.error || result.status !== 0)) {
    // No volcar argumentos/configuración o JWT a diagnósticos.
    throw new Error(result.error?.message || result.stderr?.slice(-2000) || `Docker: ${result.status}`);
  }
  return result;
}

test('PostgREST real local: write_paths, RLS y retirada sin nuestra API', { timeout: 360000 }, async t => {
  const suffix = randomUUID();
  const network = `cybersoc-8b-net-${suffix}`;
  const database = `cybersoc-8b-db-${suffix}`;
  const gateway = `cybersoc-8b-rest-${suffix}`;
  let networkCreated = false;
  let databaseAttempted = false;
  let gatewayAttempted = false;
  const sql = value => docker(['exec', '-i', '-e', 'PGCONNECT_TIMEOUT=2',
    '-e', 'PGOPTIONS=-c statement_timeout=5000', database, 'psql', '-X', '-w',
    '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-U', 'postgres', '-d', 'cybersoc_test'], value).stdout;
  const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const publicJwk = { ...publicKey.export({ format: 'jwk' }), alg: 'RS256', use: 'sig', kid: '8b-ephemeral' };
  // Firma con primitiva nativa: clave privada y JWT solo en memoria, no en logs/disco.
  function jwt(subject) {
    const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT', kid: publicJwk.kid })).toString('base64url');
    const body = Buffer.from(JSON.stringify({ sub: subject, role: 'authenticated', aud: 'authenticated',
      exp: Math.floor(Date.now() / 1000) + 600 })).toString('base64url');
    const payload = `${header}.${body}`;
    return `${payload}.${sign('RSA-SHA256', Buffer.from(payload), privateKey).toString('base64url')}`;
  }
  const tokenA = jwt(A);
  const tokenB = jwt(B);
  let base;
  async function request(path, { token = tokenA, method = 'GET', body } = {}) {
    const response = await fetch(`${base}/${path}`, {
      method, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body ? { 'Content-Type': 'application/json', Prefer: 'return=representation' } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(5000),
    });
    const text = await response.text();
    return { status: response.status, data: text ? JSON.parse(text) : null };
  }
  function success(response, status = 200) {
    assert.equal(response.status, status, `HTTP esperado ${status}; obtenido ${response.status}, código ${response.data?.code ?? '-'}`);
    return response.data;
  }
  function denied(response, status = 403) {
    assert.equal(response.status, status, `Denegación esperada ${status}; obtenida ${response.status}`);
  }
  try {
    docker(['info', '--format', '{{.ServerVersion}}']);
    // No consumir el pool automático ni limpiar redes ajenas si está lleno.
    // Subred privada propia: PostgreSQL sin puertos publicados; PostgREST solo
    // publica un puerto aleatorio en 127.0.0.1. No se hacen llamadas externas.
    for (let attempt = 0; attempt < 4 && !networkCreated; attempt += 1) {
      const subnet = `10.203.${randomInt(256)}.0/24`;
      const created = docker(['network', 'create', '--subnet', subnet, network], undefined, true);
      if (created.status === 0) networkCreated = true;
      else if (!created.stderr?.includes('Pool overlaps') || attempt === 3) {
        throw new Error(created.stderr?.slice(-1000) || created.error?.message || 'No se pudo crear red propia');
      }
    }
    databaseAttempted = true;
    docker(['run', '--detach', '--rm', '--name', database, '--network', network, '--network-alias', 'db',
      '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', '-e', 'POSTGRES_DB=cybersoc_test', postgresImage],
    undefined, false, 120000);
    await waitForPostgres(database);
    sql(readFileSync(new URL('./postgres/bootstrap.sql', import.meta.url), 'utf8'));
    for (const name of readdirSync(new URL('../supabase/migrations/', import.meta.url)).sort()) {
      sql(readFileSync(new URL(`../supabase/migrations/${name}`, import.meta.url), 'utf8'));
    }
    // Reutiliza datos ficticios del test SQL; no crea otro esquema/modelo.
    const fixture = readFileSync(new URL('./postgres/003_write_paths.sql', import.meta.url), 'utf8');
    assert.ok(fixture.includes('\nDO $test$'));
    sql(`${fixture.slice(0, fixture.indexOf('\nDO $test$'))}\nCOMMIT;`);
    sql('CREATE ROLE cybersoc_authenticator LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;\n'
      + 'GRANT anon, authenticated TO cybersoc_authenticator;');
    gatewayAttempted = true;
    docker(['run', '--detach', '--rm', '--name', gateway, '--network', network,
      '--publish', '127.0.0.1::3000',
      '-e', 'PGRST_DB_URI=postgres://cybersoc_authenticator@db:5432/cybersoc_test',
      '-e', 'PGRST_DB_SCHEMAS=public', '-e', 'PGRST_DB_ANON_ROLE=anon',
      '-e', `PGRST_JWT_SECRET=${JSON.stringify({ keys: [publicJwk] })}`,
      '-e', 'PGRST_JWT_AUD=authenticated', '-e', 'PGRST_SERVER_HOST=0.0.0.0',
      '-e', 'PGRST_LOG_LEVEL=crit', postgrestImage], undefined, false, 120000);
    const binding = docker(['port', gateway, '3000/tcp']).stdout.trim();
    assert.match(binding, /^127\.0\.0\.1:\d+$/);
    base = `http://${binding}`;
    const deadline = performance.now() + 30000;
    let ready = false;
    while (performance.now() < deadline) {
      try {
        const response = await request('app_releases?select=id', { token: null });
        if (response.status === 200) { ready = true; break; }
      } catch { /* Siguiente intento dentro del plazo, no presumir listo por esperar. */ }
      await delay(200);
    }
    assert.ok(ready, 'PostgREST debe responder dentro de 30 s');
    console.log(`PostgreSQL real: ${sql('SHOW server_version;').trim().replaceAll(/\s+/g, ' ')}`);
    console.log('PostgREST v16.5 oficial por digest; JWT RS256 efímeros; Auth simulado, no Supabase remoto.');

    await t.test('B-10: anon solo ve versiones/activos/notas publicados', async () => {
      for (const route of ['app_releases', 'release_assets']) {
        assert.equal(success(await request(route, { token: null })).length, 1);
      }
      // La fixture no necesita notas para los otros casos; el catálogo privado sigue cerrado.
      sql("INSERT INTO public.release_notes(release_id,locale,body) SELECT id,'es','Nota ficticia' FROM public.app_releases;");
      assert.equal(success(await request('release_notes', { token: null })).length, 1);
      denied(await request('device_platforms', { token: null }), 401);
      denied(await request('profiles', { token: null }), 401);
    });
    await t.test('B-01/B-08: JWT de A/B atraviesa PostgREST y RLS sin API propia', async () => {
      for (const [token, owner] of [[tokenA, A], [tokenB, B]]) {
        const rows = success(await request('profiles', { token }));
        assert.equal(rows.length, 1);
        assert.equal(rows[0].user_id, owner);
      }
      assert.deepEqual(success(await request(`profiles?user_id=eq.${B}`)), []);
      assert.deepEqual(success(await request(`user_preferences?user_id=eq.${B}`, { method: 'PATCH', body: { theme: 'dark' } })), []);
      assert.deepEqual(success(await request(`user_consents?user_id=eq.${B}`, { method: 'PATCH', body: { granted: false } })), []);
      denied(await request('profiles', { token: `${tokenA.slice(0, -10)}AAAAAAAAAA` }), 401);
    });
    await t.test('B-09: política v1 a v2, retirada con versión anterior/omitida', async () => {
      sql("UPDATE public.consent_purposes SET current_policy_version='v2' WHERE code='scan_summaries';");
      const response = success(await request('user_consents?purpose_code=eq.scan_summaries', {
        method: 'PATCH', body: { granted: false, policy_version: '2026-10-26' },
      }));
      assert.equal(response.length, 1);
      assert.equal(response[0].granted, false);
      assert.equal(response[0].policy_version, '2026-10-26');
      assert.ok(Math.abs(Date.parse(response[0].changed_at) - Date.now()) < 60000);
      const arbitrary = success(await request('user_consents?purpose_code=eq.scan_summaries', {
        method: 'PATCH', body: { granted: false, policy_version: 'NO_ACEPTADA' },
      }));
      assert.equal(arbitrary[0].policy_version, '2026-10-26');
      const omitted = success(await request('user_consents?purpose_code=eq.scan_summaries', {
        method: 'PATCH', body: { granted: false },
      }));
      assert.equal(omitted[0].policy_version, '2026-10-26');
      denied(await request('user_consents?purpose_code=eq.scan_summaries', {
        method: 'PATCH', body: { granted: true, policy_version: '2026-10-26' },
      }), 400);
      assert.equal(success(await request('user_consents?purpose_code=eq.scan_summaries', {
        method: 'PATCH', body: { granted: true, policy_version: 'v2' },
      }))[0].policy_version, 'v2');
    });
    await t.test('B-05: fechas forjadas rechazadas; INSERT de retirada normaliza la fecha', async () => {
      denied(await request('user_consents?purpose_code=eq.scan_summaries', {
        method: 'PATCH', body: { granted: false, changed_at: '2099-01-01' },
      }));
      denied(await request('user_preferences', { method: 'PATCH', body: { updated_at: '2099-01-01' } }));
      const row = success(await request('user_consents', { method: 'POST',
        body: { user_id: A, purpose_code: 'report_storage', granted: false, changed_at: '2099-01-01' },
      }), 201)[0];
      assert.equal(row.policy_version, '2026-10-26');
      assert.ok(Math.abs(Date.parse(row.changed_at) - Date.now()) < 60000);
    });
    await t.test('B-02: descarga publicada propia; B/DRAFT/fecha falsa denegados', async () => {
      denied(await request('download_requests', { method: 'POST', body: { user_id: B, asset_id: publishedAsset } }));
      denied(await request('download_requests', { method: 'POST', body: { user_id: A, asset_id: draftAsset } }));
      denied(await request('download_requests', { method: 'POST', body: { user_id: A, asset_id: publishedAsset, requested_at: '2099-01-01' } }));
      assert.equal(success(await request('download_requests', { method: 'POST', body: { user_id: A, asset_id: publishedAsset } }), 201).length, 1);
      assert.deepEqual(success(await request('download_requests', { token: tokenB })), []);
    });
    await t.test('B-03: revocar por RPC; repetida/ajena vacía; imposible reactivar', async () => {
      assert.deepEqual(success(await request('rpc/revoke_device', { method: 'POST', body: { device_id: deviceB } })), []);
      const revoked = success(await request('rpc/revoke_device', { method: 'POST', body: { device_id: deviceA } }));
      assert.equal(revoked.length, 1);
      assert.ok(Math.abs(Date.parse(revoked[0].revoked_at) - Date.now()) < 60000);
      assert.deepEqual(success(await request('rpc/revoke_device', { method: 'POST', body: { device_id: deviceA } })), []);
      assert.deepEqual(success(await request(`devices?id=eq.${deviceA}`, { method: 'PATCH', body: { revoked_at: null } })), []);
    });
    await t.test('B-03 concurrencia: dos PATCH producen una sola revocación/evento', async () => {
      const replies = await Promise.all([1, 2].map(() => request(`devices?id=eq.${deviceConcurrent}`, {
        method: 'PATCH', body: { revoked_at: '2099-01-01' },
      })));
      assert.deepEqual(replies.map(reply => success(reply).length).sort(), [0, 1]);
      const rows = success(await request(`device_events?device_id=eq.${deviceConcurrent}&event_code=eq.REVOKED`));
      assert.equal(rows.length, 1);
      assert.ok(Math.abs(Date.parse(rows[0].occurred_at) - Date.now()) < 60000);
    });
    await t.test('B-04: auditoría/eventos no falsificables, efectos propios exactos', async () => {
      denied(await request('audit_events', { method: 'POST', body: { user_id: A, event_code: 'PROFILE_CREATED' } }));
      denied(await request('device_events', { method: 'POST', body: { user_id: A, device_id: deviceA, event_code: 'REVOKED' } }));
      assert.equal(success(await request('audit_events?event_code=eq.DEVICE_REVOKED')).length, 2);
      assert.equal(success(await request('audit_events?event_code=eq.DOWNLOAD_REQUESTED')).length, 1);
      const rpc = await request('rpc/audit_write', { method: 'POST', body: {} });
      assert.ok([403, 404].includes(rpc.status));
      assert.equal(success(await request('audit_events?event_code=eq.DEVICE_REVOKED', { token: tokenB })).length, 0);
    });
  } catch (error) {
    // Solo estado/logs acotados de los recursos propios; nunca inspect del entorno.
    for (const [attempted, container] of [[databaseAttempted, database], [gatewayAttempted, gateway]]) {
      if (!attempted) continue;
      const logs = docker(['logs', '--tail', '30', container], undefined, true, 5000);
      console.error(`Diagnóstico ${container}: ${(logs.stdout || '') + (logs.stderr || '')}`);
    }
    throw error;
  } finally {
    let clean = true;
    for (const [attempted, container] of [[gatewayAttempted, gateway], [databaseAttempted, database]]) {
      if (attempted) {
        const result = docker(['rm', '--force', '--volumes', container], undefined, true, 15000);
        if (result.status !== 0) { clean = false; console.error(`Limpieza fallida del contenedor propio ${container}`); }
      }
    }
    if (networkCreated && docker(['network', 'rm', network], undefined, true, 15000).status !== 0) clean = false;
    assert.ok(clean, 'Deben retirarse contenedores, volúmenes anónimos y red propios');
    console.log('CLEANUP_PASS: recursos propios retirados; ninguna BD remota tocada.');
  }
});
