// Exercise the bundled command, its native panel and the field editor through the
// private parent pipe. No system keystrokes, pasteboard or accessibility driver.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { setTimeout as delay } from 'node:timers/promises';

const app = resolve(process.argv[2] ?? 'macos/build/UniMagic.app');
const captures = process.argv[3] && resolve(process.argv[3]);
if (captures) mkdirSync(captures, { recursive: true });
async function verify(appearance) {
  const home = mkdtempSync(join(tmpdir(), 'unimagic-picker-proof-'));
  const command = join(app, 'Contents/Helpers/PickerHost.app/Contents/MacOS/PickerHost');
  const helper = spawn(command, [], {
    env: { ...process.env, CFFIXED_USER_HOME: home, HOME: home, TINYCAST_PALETTE_NONKEY: '1',
      UNIMAGIC_FIXTURE: '1', UNIMAGIC_FIXTURE_HOME: home, UNIMAGIC_APPEARANCE: appearance },
    stdio: ['pipe', 'pipe', 'inherit'],
  });
  let ready = false, report, failure;
  const exited = new Promise(resolveExit => helper.once('exit', resolveExit));
  helper.once('error', error => { failure = error; });
  createInterface({ input: helper.stdout }).on('line', line => {
    if (line === 'ready') ready = true;
    if (line.startsWith('{')) report = JSON.parse(line);
    if (line.startsWith('error ')) failure = Error(line);
  });
  const send = line => helper.stdin.write(line + '\n');
  async function until(name, predicate) {
    const deadline = Date.now() + 25000;
    while (Date.now() < deadline) {
      if (failure) throw failure;
      if (helper.exitCode !== null || helper.signalCode) throw Error('Picker exited during ' + name);
      if (predicate()) return;
      await delay(100);
    }
    throw Error(name + ' timed out; last state: ' + JSON.stringify(report));
  }
  async function state(name, predicate) {
    await until(name, () => {
      if (report?.error) throw Error(report.error);
      if (report && predicate(report)) return true;
      send('state');
      return false;
    });
    const matched = report;
    report = undefined;
    return matched;
  }
  async function capture(name) {
    if (!captures) return;
    const path = join(captures, name + '-' + appearance + '.png');
    rmSync(path, { force: true });
    send('capture ' + path);
    await until('capture ' + name, () => existsSync(path));
  }
  try {
    await until('helper boot', () => ready);
    send('invoke');
    const opened = await state('first invocation', r => r.visible && r.count > 8);
    assert.equal(opened.appearance, appearance === 'dark' ? 'NSAppearanceNameDarkAqua' : 'NSAppearanceNameAqua');
    console.log(appearance + ': ' + opened.appearance);
    send('invoke');
    await state('untouched immediate repeat dismisses', r => !r.visible);
    send('show');
    await state('reopen', r => r.visible && r.count > 8);
    send('query arrow');
    await state('query and rendered results', r => r.query === 'arrow' && r.actions?.some(s => /arrow/i.test(s)));
    await capture('picker');
    send('scrollEnd');
    await state('scrolling the native viewport appends another page', r => r.count > 200);
    await state('search field focused with only a caret', r => r.field === 'arrow' && r.range?.[1] === 0);
    send('key selectAll');
    await state('selection covers the query', r => r.range?.[0] === 0 && r.range?.[1] === 5);
    send('key x');
    await state('typing replaces selection', r => r.query === 'x' && r.field === 'x');
    send('query ');
    const empty = await state('empty focused search', r => r.query === '' && r.field === '' && r.count > 8);
    send('key right');
    await state('empty focused search moves grid selection', r => r.selected === empty.selected + 1 && r.field === '');
    send('query U+1F44B');
    await state('tone-capable selection', r => r.query === 'U+1F44B' && r.actions?.some(s => s.includes('Skin Tones')));
    send('invoke');
    const tones = await state('selected glyph tones', r => r.depth > 1 && r.count >= 6);
    assert.ok(tones.visible);
    await capture('tones');
    send('key escape');
    await state('return to search', r => r.depth === 1 && r.query === 'U+1F44B');
    console.log(appearance + ': real command and panel, immediate dismiss, ⌘A replacement, empty-search grid arrow, tones and return passed.');
  } finally {
    helper.stdin.end();
    const timer = setTimeout(() => helper.kill(), 3000);
    await exited;
    clearTimeout(timer);
    rmSync(home, { recursive: true, force: true });
  }
}
await verify('light');
if (captures) await verify('dark');
