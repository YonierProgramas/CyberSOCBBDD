import assert from 'node:assert/strict';
import test from 'node:test';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import { probePostgres, waitForPostgres } from '../scripts/test-postgres.mjs';

function docker(args, input, allowFailure = false, timeout = 5000) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', windowsHide: true,
    timeout, killSignal: 'SIGKILL', maxBuffer: 4 * 1024 * 1024 });
  if (!allowFailure && (result.error || result.status !== 0)) {
    throw new Error(result.error?.message || result.stderr || `Docker: ${result.status}`);
  }
  return result;
}

async function waitForMarker(container, marker) {
  const deadline = performance.now() + 30000;
  while (performance.now() < deadline) {
    const result = docker(['exec', container, 'test', '-f', marker], undefined, true,
      Math.max(1, Math.min(5000, Math.ceil(deadline - performance.now()))));
    if (!result.error && result.status === 0) return;
    await delay(100);
  }
  throw new Error(`Timeout esperando la fase ${marker}.`);
}

test('regresión real: pg_isready acepta BD ausente; readiness rechaza ambas fases temporales', { timeout: 360000 }, async () => {
  const container = `cybersoc-readiness-${randomUUID()}`;
  const image = process.env.CYBERSOC_TEST_POSTGRES_IMAGE ?? 'postgres:17-alpine';
  // Git puede usar CRLF en Windows; bash dentro de Linux necesita saltos LF.
  const entrypoint = readFileSync(new URL('./fixtures/readiness-entrypoint.sh', import.meta.url), 'utf8')
    .replaceAll('\r\n', '\n');
  assert.match(image, /^postgres(?::[a-zA-Z0-9._-]+|@sha256:[a-f0-9]{64})$/);
  docker(['info', '--format', '{{.ServerVersion}}'], undefined, false, 15000);
  try {
    // Sin red externa, puertos publicados ni montajes del usuario. PGDATA es nuevo.
    // --user postgres evita que _main se relance como root y pierda las puertas.
    docker(['run', '--detach', '--rm', '--name', container, '--network', 'none',
      '--user', 'postgres', '-e', 'PGDATA=/tmp/cybersoc-readiness-data',
      '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', '-e', 'POSTGRES_DB=cybersoc_test',
      '--entrypoint', 'bash', image, '-c', entrypoint],
    undefined, false, 240000);

    await waitForMarker(container, '/tmp/cybersoc-before-db');
    const oldProbe = docker(['exec', container, 'pg_isready', '-U', 'postgres', '-d', 'cybersoc_test']);
    assert.equal(oldProbe.status, 0);
    const absent = docker(['exec', container, 'psql', '-X', '-w', '-U', 'postgres',
      '-d', 'cybersoc_test', '-c', 'SELECT 1'], undefined, true);
    assert.notEqual(absent.status, 0);
    assert.match(absent.stderr, /database "cybersoc_test" does not exist/);
    console.log(`ANTES: pg_isready=${oldProbe.status}; SQL=${absent.status}: ${absent.stderr.trim()}`);
    await assert.rejects(waitForPostgres(container, { run: docker, timeoutMs: 1200 }), /no disponible/);

    docker(['exec', container, 'touch', '/tmp/cybersoc-allow-db']);
    await waitForMarker(container, '/tmp/cybersoc-after-db');
    const temporary = docker(['exec', container, 'psql', '-X', '-w', '-A', '-t',
      '-U', 'postgres', '-d', 'cybersoc_test', '-c', 'SELECT current_database()']);
    assert.equal(temporary.stdout.trim(), 'cybersoc_test');
    const tcp = probePostgres(container, docker);
    assert.notEqual(tcp.status, 0);
    await assert.rejects(waitForPostgres(container, { run: docker, timeoutMs: 1200 }), /no disponible/);
    console.log('INTERMEDIO: BD existente por socket; TCP rechazado durante servidor temporal.');

    docker(['exec', container, 'touch', '/tmp/cybersoc-allow-final']);
    const ready = await waitForPostgres(container, { run: docker });
    console.log(`DESPUÉS: consulta real TCP PASS en ${ready.attempts} intentos.`);
  } catch (error) {
    const logs = docker(['logs', '--tail', '80', container], undefined, true);
    console.error(`${logs.stdout || ''}${logs.stderr || ''}${logs.error?.message || ''}`);
    throw error;
  } finally {
    docker(['rm', '--force', '--volumes', container]);
  }
});
