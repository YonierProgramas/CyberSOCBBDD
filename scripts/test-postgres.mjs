import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function docker(args, input, allowFailure = false, timeout = 30000) {
  const result = spawnSync('docker', args, {
    input, encoding: 'utf8', windowsHide: true, timeout, killSignal: 'SIGKILL',
    maxBuffer: 4 * 1024 * 1024,
  });
  if (!allowFailure && (result.error || result.status !== 0)) {
    throw new Error(result.error?.message || result.stderr?.trim() || `Falló Docker (estado ${result.status}).`);
  }
  return result;
}

// TCP excluye al servidor temporal de la imagen oficial, que solo abre un socket.
// -X/-w evitan configuración interactiva; PGOPTIONS limita también la consulta.
export function probePostgres(container, run = docker, timeout = 5000) {
  return run(['exec', '-e', 'PGCONNECT_TIMEOUT=2', '-e', 'PGOPTIONS=-c statement_timeout=2000',
    container, 'psql', '-X', '-w', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
    '-h', '127.0.0.1', '-p', '5432', '-U', 'postgres', '-d', 'cybersoc_test',
    '-c', "SELECT current_database() || '|' || (inet_server_addr() IS NOT NULL)::text;"],
  undefined, true, timeout);
}

export async function waitForPostgres(container, {
  run = docker, now = () => performance.now(), sleep = delay,
  timeoutMs = 60000, pollMs = 250,
} = {}) {
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0 || !Number.isFinite(pollMs) || pollMs <= 0) {
    throw new Error('Los límites de readiness deben ser positivos y finitos.');
  }
  const deadline = now() + timeoutMs;
  let attempts = 0;
  let last = 'Sin respuesta.';
  while (now() < deadline) {
    const result = probePostgres(container, run, Math.max(1, Math.min(5000, Math.ceil(deadline - now()))));
    attempts += 1;
    if (!result.error && result.status === 0 && result.stdout?.trim() === 'cybersoc_test|true' && now() < deadline) {
      return { attempts };
    }
    last = (result.error?.message || result.stderr?.trim() || result.stdout?.trim() || `estado ${result.status}`).slice(-2000);
    const remaining = deadline - now();
    // Intervalo solo entre consultas fallidas; no se presume listo por haber esperado.
    if (remaining > 0) await sleep(Math.min(pollMs, remaining));
  }
  throw new Error(`PostgreSQL no disponible en cybersoc_test por TCP 127.0.0.1:5432 en ${timeoutMs} ms (${attempts} intentos). Último resultado: ${last}`);
}

function sqlFile(container, file) {
  const result = docker(['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
    '-w', '-h', '127.0.0.1', '-p', '5432', '-U', 'postgres', '-d', 'cybersoc_test'], readFileSync(file, 'utf8'));
  process.stdout.write(result.stdout);
}

export async function runPostgresTests() {
  const container = `cybersoc-db-test-${randomUUID()}`;
  const image = process.env.CYBERSOC_TEST_POSTGRES_IMAGE ?? 'postgres:17-alpine';
  if (!/^postgres(?::[a-zA-Z0-9._-]+|@sha256:[a-f0-9]{64})$/.test(image)) {
    throw new Error('Usa únicamente una etiqueta o digest oficial de postgres.');
  }
  let attempted = false;
  try {
    docker(['info', '--format', '{{.ServerVersion}}'], undefined, false, 15000);
    // Sin puertos publicados, volúmenes del usuario ni red del contenedor.
    attempted = true;
    docker(['run', '--detach', '--rm', '--name', container, '--network', 'none',
      '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', '-e', 'POSTGRES_DB=cybersoc_test', image], undefined, false, 240000);
    const { attempts } = await waitForPostgres(container);
    console.log(`PostgreSQL listo: consulta real TCP a cybersoc_test (${attempts} intentos).`);
    sqlFile(container, resolve(root, 'tests/postgres/bootstrap.sql'));
    for (const name of readdirSync(resolve(root, 'supabase/migrations')).sort()) {
      console.log(`Migración: ${name}`);
      sqlFile(container, resolve(root, 'supabase/migrations', name));
    }
    for (const name of readdirSync(resolve(root, 'tests/postgres')).filter(name => name !== 'bootstrap.sql').sort()) {
      console.log(`Prueba: ${name}`);
      sqlFile(container, resolve(root, 'tests/postgres', name));
    }
    console.log('POSTGRES_TESTS_PASS: migraciones, 30 tablas, integridad y RLS.');
  } catch (error) {
    console.error(error.message);
    if (attempted) {
      const state = docker(['inspect', '--format', '{{json .State}}', container], undefined, true, 5000);
      const logs = docker(['logs', '--tail', '80', container], undefined, true, 5000);
      console.error(`Estado del contenedor propio: ${state.stdout || state.stderr || state.error?.message}`);
      console.error(`Últimos logs del contenedor propio:\n${logs.stdout || ''}${logs.stderr || ''}${logs.error?.message || ''}`);
    }
    process.exitCode = 1;
  } finally {
    if (attempted) {
      const cleanup = docker(['rm', '--force', '--volumes', container], undefined, true);
      if (cleanup.status !== 0) {
        console.error(`No se pudo retirar el contenedor temporal ${container}.`);
        process.exitCode = 1;
      }
    }
  }
}

// Importar readiness en las pruebas no inicia Docker ni ejecuta migraciones.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await runPostgresTests();
}
