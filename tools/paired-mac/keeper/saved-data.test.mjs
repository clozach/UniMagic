import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync} from 'node:fs';
import {join, dirname, basename} from 'node:path';
import {tmpdir} from 'node:os';
import {compareSavedData} from './saved-data.mjs';
import {savedHashes, installAndVerify} from './device.mjs';

const state = 'support/PowWorm/state.json';
const unchanged = {'support/unimagic/learning.json': '{"uses":3}', 'preferences/app.plist': Buffer.from([0, 255, 1, 2])};
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'pw-saved-data-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const capture = (folder, files) => {
    mkdirSync(folder, {recursive: true});
    for (const [name, bytes] of Object.entries(files)) {
      const path = join(folder, name);
      mkdirSync(dirname(path), {recursive: true});
      writeFileSync(path, bytes);
    }
    return savedHashes(folder);
  };
  const compare = (before, after) => {
    const left = join(root, 'before'), right = join(root, 'after');
    rmSync(left, {recursive: true, force: true}); rmSync(right, {recursive: true, force: true});
    return compareSavedData(capture(left, before), capture(right, after), left, right);
  };
  return {root, capture, compare};
}

test('known state permits object key order, whitespace and equivalent string escapes with both hashes retained', t => {
  const f = fixture(t);
  const before = '{"messages":[{"id":"a","text":"hello"}],"settings":{"enabled":true,"limit":9007199254740993}}';
  const after = '{\n "settings": {"limit":9007199254740993, "enabled":true}, "messages":[{"text":"h\\u0065llo","id":"a"}]\n}';
  const result = f.compare({...unchanged, [state]: before}, {[state]: after, ...unchanged});
  assert.equal(result.length, 3);
  const changed = result.find(x => x.path === state);
  assert.equal(changed.comparison, 'json-formatting-only');
  assert.notEqual(changed.beforeSHA256, changed.afterSHA256);
  for (const item of result.filter(x => x.path !== state)) {
    assert.equal(item.comparison, 'byte-identical');
    assert.equal(item.beforeSHA256, item.afterSHA256);
  }
  assert.equal(readFileSync(join(f.root, 'before', state), 'utf8'), before);
  assert.equal(readFileSync(join(f.root, 'after', state), 'utf8'), after);
});

test('byte equality remains the fast path for every file and hash map order is irrelevant', () => {
  const before = {[state]: 'same-state-hash', other: 'same-other-hash'};
  const after = {other: 'same-other-hash', [state]: 'same-state-hash'};
  assert.deepEqual(compareSavedData(before, after, '/not/read', '/not/read').map(x => x.comparison), ['byte-identical', 'byte-identical']);
});

test('adding or removing any saved file fails, even when the state itself is unchanged', t => {
  const f = fixture(t), before = {...unchanged, [state]: '{}'};
  assert.throws(() => f.compare(before, {[state]: '{}'}), /inventory differs/);
  assert.throws(() => f.compare(before, {...before, extra: 'new data'}), /inventory differs/);
});

test('only the exact known state path accepts formatting changes', t => {
  const f = fixture(t);
  for (const path of ['support/unimagic/learning.json', 'support/Other/state.json', 'support/PowWorm/State.json', 'preferences/state.json']) {
    assert.throws(() => f.compare({[path]: '{"a":1,"b":2}'}, {[path]: '{"b":2, "a":1}'}), /Saved data changed/);
  }
});

test('nested values, array order, types and object membership remain exact', t => {
  const f = fixture(t);
  const cases = [
    ['{"nested":{"text":"old"}}', '{"nested":{"text":"new"}}'],
    ['{"items":[1,2]}', '{"items":[2,1]}'],
    ['{"value":1}', '{"value":"1"}'],
    ['{"value":true}', '{"value":false}'],
    ['{"value":null}', '{"value":"null"}'],
    ['{"value":[]}', '{"value":{}}'],
    ['{"a":1}', '{"a":1,"b":2}'],
    ['{"a":1,"b":2}', '{"a":1}'],
  ];
  for (const [before, after] of cases) assert.throws(() => f.compare({[state]: before}, {[state]: after}), /JSON content differs/);
});

test('numbers never round, overflow or underflow into equality; alternate spellings conservatively fail', t => {
  const f = fixture(t);
  for (const [before, after] of [['9007199254740993', '9007199254740992'], ['1e400', '2e400'], ['1e-400', '0'], ['-0', '0'], ['1', '1.0']]) {
    assert.throws(() => f.compare({[state]: '{"n":' + before + '}'}, {[state]: '{"n":' + after + '}'}), /JSON content differs/);
  }
  assert.equal(f.compare({[state]: '{"n":1e400}'}, {[state]: '{ "n" : 1e400 }'})[0].comparison, 'json-formatting-only');
});

test('changed malformed JSON, duplicate decoded keys and invalid UTF-8 fail without repair', t => {
  const f = fixture(t);
  const malformed = ['{"a":1,}', '{"a":1 "b":2}', '{"a":01}', '{"a":NaN}', '{"a":"\\x00"}', '{"a":1} trailing', '{"a":1,"a":1}', '{"a":1,"\\u0061":1}', '\uFEFF{"a":1}', '['.repeat(130) + '0' + ']'.repeat(130), Buffer.from([123, 34, 97, 34, 58, 34, 255, 34, 125])];
  for (const after of malformed) assert.throws(() => f.compare({[state]: '{"a":1}'}, {[state]: after}), /malformed, ambiguous or changed snapshot/);
  assert.throws(() => f.compare({[state]: '{"a":1,"a":1}'}, {[state]: '{"a":1}'}), /malformed, ambiguous or changed snapshot/);
});

test('snapshot changes after hashing fail instead of producing stale verification', t => {
  const f = fixture(t), left = join(f.root, 'before'), right = join(f.root, 'after');
  const before = f.capture(left, {[state]: '{"a":1}'}), after = f.capture(right, {[state]: '{ "a":1 }'});
  writeFileSync(join(right, state), '{"a":2}');
  assert.throws(() => compareSavedData(before, after, left, right), /changed snapshot/);
  assert.equal(readFileSync(join(right, state), 'utf8'), '{"a":2}');
});

for (const allowUpgrade of [false, true]) test((allowUpgrade ? 'managed upgrade' : 'renewal') + ' uses retained real snapshots and returns the comparison receipt', async t => {
  const f = fixture(t), calls = [], release = {build: '11', version: '1.1.0', installedURL: 'old'};
  let installed = {bundleIdentifier:'com.clozach.amaanah.alerts',bundleVersion: allowUpgrade ? '10' : '11', version: '1.1.0', url: 'old'};
  const result = await installAndVerify('/fixture.app', release, f.root, {
    allowUpgrade, installedApp: async () => installed,
    snapshotSaved: async folder => f.capture(folder, {...unchanged, [state]: basename(folder) === 'saved-before' ? '{"a":1,"b":2}' : '{"b":2, "a":1}'}),
    device: async args => { calls.push(args); installed = {...installed, bundleVersion: '11', url: 'new'}; return {success: true}; },
  });
  assert.deepEqual(calls, [['install', 'app', '/fixture.app']]);
  assert.equal(result.savedFiles, 3);
  assert.equal(result.installedURL, 'new');
  assert.equal(result.savedData.find(x => x.path === state).comparison, 'json-formatting-only');
  for (const suffix of ['saved-before', 'saved-after']) assert.deepEqual(readFileSync(join(f.root, suffix, 'preferences/app.plist')), unchanged['preferences/app.plist']);
});

test('real changed state after install fails and retains both snapshots without restoring either', async t => {
  const f = fixture(t), calls = [];
  await assert.rejects(installAndVerify('/fixture.app', {build: '11', version: '1.1.0', installedURL: 'same'}, f.root, {
    installedApp: async () => ({bundleIdentifier:'com.clozach.amaanah.alerts',bundleVersion: '11', version: '1.1.0', url: 'same'}),
    snapshotSaved: async folder => f.capture(folder, {[state]: basename(folder) === 'saved-before' ? '{"draft":"old"}' : '{"draft":"new"}'}),
    device: async args => { calls.push(args); return {success: true}; },
  }), /JSON content differs/);
  assert.deepEqual(calls, [['install', 'app', '/fixture.app']]);
  assert.equal(readFileSync(join(f.root, 'saved-before', state), 'utf8'), '{"draft":"old"}');
  assert.equal(readFileSync(join(f.root, 'saved-after', state), 'utf8'), '{"draft":"new"}');
});
