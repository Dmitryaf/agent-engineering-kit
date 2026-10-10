import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const hubRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const temporaryBase = resolve(tmpdir());
const fixtureRoot = mkdtempSync(join(temporaryBase, 'aek-materials-'));
const offline = process.argv.includes('--offline');

function write(root, path, content) {
  const destination = join(root, path);
  mkdirSync(dirname(destination), { recursive: true });
  writeFileSync(destination, content);
}

function run(root, executable, args, expectedSuccess = true) {
  const npmCli = executable === 'npm' ? process.env.npm_execpath : undefined;
  const command = npmCli ? process.execPath : executable;
  const commandArgs = npmCli ? [npmCli, ...args] : args;
  const result = spawnSync(command, commandArgs, {
    cwd: root, encoding: 'utf8', timeout: 180_000,
    // Only fixed npm commands use the Windows command shim; paths use cwd.
    shell: process.platform === 'win32' && command === 'npm'
  });
  assert.ifError(result.error);
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  assert.equal(result.status === 0, expectedSuccess, `${executable} ${args.join(' ')}\n${output}`);
  return output;
}

function prepare(name) {
  const root = join(fixtureRoot, name);
  cpSync(join(hubRoot, 'templates/technical', name), root, { recursive: true });
  write(root, 'package.json', readFileSync(join(root, 'package.example.json'), 'utf8'));
  const npmVersion = run(root, 'npm', ['--version']).trim();
  assert(Number(npmVersion.split('.')[0]) >= 11, 'Use npm 11 for this verified combination; npm_execpath can point to its npm-cli.js without changing the global installation.');
  console.log(`${name}: installing exact direct dependencies in a temporary fixture`);
  run(root, 'npm', ['install', '--ignore-scripts', '--no-audit', '--no-fund', ...(offline ? ['--offline'] : [])]);
  return root;
}

function probeBoundaries(root, examples) {
  const probePath = 'src/logic/forbidden.ts';
  const eslint = join(root, 'node_modules/eslint/bin/eslint.js');
  for (const [source, rule] of examples) {
    write(root, probePath, source);
    const result = run(root, process.execPath, [eslint, probePath, '--format', 'json'], false);
    const messages = JSON.parse(result)[0].messages;
    assert(messages.some(message => message.ruleId === rule), `Expected ${rule} for ${source}`);
  }
  rmSync(join(root, probePath));
}

function probeTypes(root, command) {
  const path = 'src/invalid-type.ts';
  write(root, path, 'export const invalid: string = 7;\n');
  const output = run(root, process.execPath, command, false);
  assert(output.includes('TS2322'), 'Type checking must reject an actual incompatible assignment');
  rmSync(join(root, path));
}

try {
  const vue = prepare('vue-vite');
  write(vue, 'index.html', '<html><body><div id="app"></div><script type="module" src="/src/main.ts"></script></body></html>\n');
  write(vue, 'src/main.ts', "import { createApp } from 'vue';\nimport App from './App.vue';\ncreateApp(App).mount('#app');\n");
  write(vue, 'src/App.vue', `<script setup lang="ts">
import { formatCount } from './logic/count';
</script>
<template>
  <p>{{ formatCount(2) }}</p>
</template>
`);
  write(vue, 'src/logic/count.ts', `export function formatCount(count: number): string {
  if (!Number.isInteger(count) || count < 0) throw new Error('Invalid count');
  return String(count);
}
`);
  write(vue, 'src/logic/count.test.ts', `import { expect, test } from 'vitest';
import { formatCount } from './count';
test('count preserves zero and rejects invalid input', () => {
  expect(formatCount(0)).toBe('0');
  expect(formatCount(2)).toBe('2');
  expect(() => formatCount(-1)).toThrow('Invalid count');
  expect(() => formatCount(1.5)).toThrow('Invalid count');
});
`);
  const vueChecks = run(vue, 'npm', ['run', 'check']);
  assert(vueChecks.includes('1 passed'), 'Vitest must run the actual behavior test');
  assert(existsSync(join(vue, 'dist/index.html')), 'Vite must build the actual SFC entry point');
  probeBoundaries(vue, [
    ["import { ref } from 'vue'; export const value = ref(0);", 'no-restricted-imports'],
    ["export { ref } from 'vue';", 'no-restricted-imports'],
    ["export const load = () => import('vue');", 'no-restricted-syntax'],
    ["export { default } from '../App.vue';", 'no-restricted-imports']
  ]);
  probeTypes(vue, [join(vue, 'node_modules/vue-tsc/bin/vue-tsc.js'), '--noEmit']);
  write(vue, 'src/Invalid.vue', '<script setup lang="ts">const count: number = "wrong";</script><template><p>{{ count }}</p></template>');
  const invalidSfc = run(vue, process.execPath, [join(vue, 'node_modules/vue-tsc/bin/vue-tsc.js'), '--noEmit'], false);
  assert(invalidSfc.includes('Invalid.vue') && invalidSfc.includes('TS2322'), 'SFC type errors must also be observed');
  rmSync(join(vue, 'src/Invalid.vue'));
  console.log('vue-vite: types, SFC lint/build, behavior and boundary rejection passed');

  const service = prepare('node-service');
  write(service, 'src/logic/label.ts', `export function normalizeLabel(input: string): string {
  const value = input.trim();
  if (!value) throw new Error('Empty label');
  return value;
}
`);
  write(service, 'src/server.ts', `import { createServer } from 'node:http';
import { normalizeLabel } from './logic/label.js';
export function createLabelServer() {
  return createServer((request, response) => {
    const value = new URL(request.url ?? '/', 'http://localhost').searchParams.get('label');
    try {
      response.setHeader('Content-Type', 'application/json');
      response.end(JSON.stringify({ label: normalizeLabel(value ?? '') }));
    } catch {
      response.writeHead(400).end(JSON.stringify({ error: 'Invalid label' }));
    }
  });
}
`);
  write(service, 'src/logic/label.test.ts', `import assert from 'node:assert/strict';
import { test } from 'node:test';
import { normalizeLabel } from './label.js';
test('normalization preserves data and rejects an empty label', () => {
  assert.equal(normalizeLabel('  hello  '), 'hello');
  assert.throws(() => normalizeLabel(' '), /Empty label/);
});
`);
  write(service, 'src/server.test.ts', `import assert from 'node:assert/strict';
import { once } from 'node:events';
import { test } from 'node:test';
import { createLabelServer } from './server.js';
test('HTTP returns the normalized label and a truthful invalid-input response', { timeout: 10_000 }, async t => {
  const server = createLabelServer();
  t.after(() => new Promise<void>((resolve, reject) => {
    server.close(error => error ? reject(error) : resolve());
  }));
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  assert(address && typeof address !== 'string');
  const base = 'http://127.0.0.1:' + address.port;
  const response = await fetch(base + '/?label=%20hello%20');
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { label: 'hello' });
  const invalid = await fetch(base + '/?label=%20');
  assert.equal(invalid.status, 400);
  assert.deepEqual(await invalid.json(), { error: 'Invalid label' });
});
`);
  const serviceChecks = run(service, 'npm', ['run', 'check']);
  assert(serviceChecks.includes('# pass 2'), 'Node must discover both the logic and HTTP tests');
  probeBoundaries(service, [
    ["import { readFile } from 'node:fs'; export { readFile };", 'no-restricted-imports'],
    ["import { readFile } from 'fs'; export { readFile };", 'no-restricted-imports'],
    ["export { createLabelServer } from '../server.js';", 'no-restricted-imports'],
    ["export const load = () => import('node:fs');", 'no-restricted-syntax']
  ]);
  probeTypes(service, [join(service, 'node_modules/typescript/bin/tsc'), '--noEmit']);
  console.log('node-service: types, lint, native tests, HTTP and boundary rejection passed');
  console.log('Both technical materials passed. This does not verify product design, deployment or bootstrap speed.');
} finally {
  // mkdtemp created this directory. Verify its absolute boundary before removal.
  const withinTemp = relative(temporaryBase, fixtureRoot);
  assert(withinTemp.startsWith('aek-materials-') && !withinTemp.includes(sep));
  assert.equal(dirname(fixtureRoot), temporaryBase);
  if (process.argv.includes('--keep')) console.log(`Temporary evidence retained: ${fixtureRoot}`);
  else rmSync(fixtureRoot, { recursive: true, force: false });
}
