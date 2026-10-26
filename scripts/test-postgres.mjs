import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const container = `cybersoc-db-test-${randomUUID()}`;
const image = process.env.CYBERSOC_TEST_POSTGRES_IMAGE ?? 'postgres:17-alpine';
if (!/^postgres(?::[a-zA-Z0-9._-]+|@sha256:[a-f0-9]{64})$/.test(image)) {
  throw new Error('Usa únicamente una etiqueta o digest oficial de postgres.');
}

function docker(args, input, allowFailure = false, timeout = 30000) {
  const result = spawnSync('docker', args, {
    input, encoding: 'utf8', windowsHide: true, timeout, killSignal: 'SIGKILL',
    maxBuffer: 4 * 1024 * 1024,
  });
  if (!allowFailure && (result.error || result.status !== 0)) {
    throw new Error(result.error?.message ?? result.stderr ?? 'Falló Docker.');
  }
  return result;
}

function sqlFile(file) {
  const result = docker(['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
    '-U', 'postgres', '-d', 'cybersoc_test'], readFileSync(file, 'utf8'));
  process.stdout.write(result.stdout);
}

let started = false;
try {
  docker(['info', '--format', '{{.ServerVersion}}'], undefined, false, 15000);
  // Sin puertos publicados, volúmenes del usuario ni red del contenedor.
  docker(['run', '--detach', '--rm', '--name', container, '--network', 'none',
    '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', '-e', 'POSTGRES_DB=cybersoc_test', image], undefined, false, 240000);
  started = true;
  let ready = false;
  for (let attempt = 0; attempt < 80; attempt += 1) {
    if (docker(['exec', container, 'pg_isready', '-U', 'postgres', '-d', 'cybersoc_test'], undefined, true).status === 0) {
      ready = true;
      break;
    }
    await delay(500);
  }
  if (!ready) throw new Error('PostgreSQL de prueba no estuvo listo dentro del límite.');
  sqlFile(resolve(root, 'tests/postgres/bootstrap.sql'));
  for (const name of readdirSync(resolve(root, 'supabase/migrations')).sort()) {
    console.log(`Migración: ${name}`);
    sqlFile(resolve(root, 'supabase/migrations', name));
  }
  for (const name of readdirSync(resolve(root, 'tests/postgres')).filter(name => name !== 'bootstrap.sql').sort()) {
    console.log(`Prueba: ${name}`);
    sqlFile(resolve(root, 'tests/postgres', name));
  }
  console.log('POSTGRES_TESTS_PASS: migraciones, 30 tablas, integridad y RLS.');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  if (started) {
    const cleanup = docker(['rm', '--force', container], undefined, true);
    if (cleanup.status !== 0) {
      console.error(`No se pudo retirar el contenedor temporal ${container}.`);
      process.exitCode = 1;
    }
  }
}
