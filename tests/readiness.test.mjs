import assert from 'node:assert/strict';
import test from 'node:test';
import { probePostgres, waitForPostgres } from '../scripts/test-postgres.mjs';

const ok = { status: 0, stdout: 'cybersoc_test|true\n', stderr: '' };
const missing = { status: 2, stdout: '', stderr: 'FATAL: database "cybersoc_test" does not exist' };

function clock() {
  let time = 0;
  const waits = [];
  return { now: () => time, advance: ms => { time += ms; },
    sleep: async ms => { waits.push(ms); time += ms; }, waits };
}

test('la consulta verifica BD real por TCP, sin socket ni configuración interactiva', () => {
  probePostgres('own-test', (args, input, allowFailure, timeout) => {
    assert.deepEqual(args.slice(0, 7), ['exec', '-e', 'PGCONNECT_TIMEOUT=2', '-e',
      'PGOPTIONS=-c statement_timeout=2000', 'own-test', 'psql']);
    assert.equal(args[args.indexOf('-h') + 1], '127.0.0.1');
    assert.equal(args[args.indexOf('-d') + 1], 'cybersoc_test');
    assert.ok(args.includes('-X') && args.includes('-w') && args.includes('ON_ERROR_STOP=1'));
    assert.match(args.at(-1), /current_database\(\)/);
    assert.match(args.at(-1), /inet_server_addr\(\) IS NOT NULL/);
    assert.equal(input, undefined);
    assert.equal(allowFailure, true);
    assert.equal(timeout, 5000);
    return ok;
  });
});

test('reintenta BD inexistente, socket temporal y respuesta incompleta antes del servidor final', async () => {
  const timing = clock();
  const replies = [missing, { status: 0, stdout: 'cybersoc_test|false' },
    { status: 0, stdout: '' }, { status: 0, stdout: 'postgres|true' }, ok];
  let calls = 0;
  const result = await waitForPostgres('own-test', { ...timing,
    run: () => replies[calls++], timeoutMs: 5000 });
  assert.equal(calls, 5);
  assert.equal(result.attempts, 5);
  assert.deepEqual(timing.waits, [250, 250, 250, 250]);
});

test('timeout global acota cada comando e intervalo y conserva el diagnóstico', async () => {
  const timing = clock();
  const budgets = [];
  await assert.rejects(waitForPostgres('own-test', { ...timing, timeoutMs: 600,
    run: (_args, _input, _allowFailure, budget) => { budgets.push(budget); return missing; },
  }), /600 ms \(3 intentos\).*database "cybersoc_test" does not exist/);
  assert.deepEqual(budgets, [600, 350, 100]);
  assert.deepEqual(timing.waits, [250, 250, 100]);
  assert.equal(timing.now(), 600);
});

test('un comando que agota el plazo no provoca otro intento ni un PASS tardío', async () => {
  const timing = clock();
  let calls = 0;
  await assert.rejects(waitForPostgres('own-test', { ...timing, timeoutMs: 900,
    run: () => { calls += 1; timing.advance(900); return ok; },
  }), /900 ms \(1 intentos\)/);
  assert.equal(calls, 1);
  assert.deepEqual(timing.waits, []);
});

test('error/timeout del proceso nunca se acepta aunque contenga salida de éxito', async () => {
  const timing = clock();
  await assert.rejects(waitForPostgres('own-test', { ...timing, timeoutMs: 100,
    run: () => ({ ...ok, error: new Error('spawnSync docker ETIMEDOUT') }),
  }), /ETIMEDOUT/);
});

test('rechaza límites inválidos antes de ejecutar Docker', async () => {
  for (const limits of [{ timeoutMs: 0 }, { timeoutMs: Infinity }, { pollMs: -1 }, { pollMs: NaN }]) {
    await assert.rejects(waitForPostgres('own-test', { ...limits,
      run: () => assert.fail('No debe ejecutar Docker'),
    }), /positivos y finitos/);
  }
});
