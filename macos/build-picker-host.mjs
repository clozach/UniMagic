// Build Tinycast's single-command helper from its pinned public source. It is a
// separate AGPL executable. The MIT controller talks to it through standard I/O.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = join(dirname(fileURLToPath(import.meta.url)), 'picker-host');
const revision = readFileSync(join(directory, 'TINYCAST_REVISION'), 'utf8').trim();
if (!/^[a-f0-9]{40}$/.test(revision)) throw Error('Expected a full Tinycast source commit.');
const origin = 'https://github.com/clozach/tinycast.git';

export function buildPickerHost(app, identity) {
  const work = mkdtempSync(join(tmpdir(), 'unimagic-picker-host-'));
  const run = (command, args, options = {}) =>
    execFileSync(command, args, {cwd: work, stdio: 'inherit', ...options});
  const cache = process.env.UNIMAGIC_PICKER_BUILD_CACHE;
  const fingerprint = createHash('sha256');
  for (const name of ['TINYCAST_REVISION','project.yml','SingleCommandMain.swift','HostInteraction.swift','single-command.patch']) {
    fingerprint.update(name).update(readFileSync(join(directory, name)));
  }
  fingerprint.update(readFileSync(fileURLToPath(import.meta.url)));
  fingerprint.update(process.arch).update(execFileSync('xcodebuild', ['-version']));
  const cacheKey = fingerprint.digest('hex');
  const cached = cache && join(cache, cacheKey, 'PickerHost.app');
  let products;
  try {
    if (cached && existsSync(cached)) {
      run('codesign', ['--verify','--strict',cached]);
      products = cached;
    } else {
      let repository = process.env.UNIMAGIC_TINYCAST_SOURCE;
      if (!repository) {
        repository = join(work, 'source.git');
        run('git', ['init', '--bare', '--quiet', repository]);
        run('git', ['-C', repository, 'fetch', '--quiet', '--depth=1', origin, revision]);
      }
      const archive = join(work, 'tinycast.tar');
      run('git', ['-C', repository, 'archive', '--format=tar', '-o', archive, revision, 'Tinycast', 'LICENSE', 'NOTICE.md']);
      run('tar', ['-xf', archive]);
      run('git', ['apply', join(directory, 'single-command.patch')]);
      for (const name of ['project.yml', 'SingleCommandMain.swift', 'HostInteraction.swift']) {
        cpSync(join(directory, name), join(work, name));
      }
      run('xcodegen', ['generate']);
      const derived = join(work, 'Derived');
      run('xcodebuild', ['-quiet', '-project', 'PickerHost.xcodeproj', '-scheme', 'PickerHost',
        '-configuration', 'Release', '-destination', 'platform=macOS,arch=' + (process.arch === 'arm64' ? 'arm64' : 'x86_64'),
        '-derivedDataPath', derived, 'build']);
      products = join(derived, 'Build/Products/Release/PickerHost.app');
      run('strip', ['-x', join(products,'Contents/MacOS/PickerHost')]);
      cpSync(join(work, 'LICENSE'), join(products, 'Contents/Resources/LICENSE'));
      cpSync(join(work, 'NOTICE.md'), join(products, 'Contents/Resources/NOTICE.md'));
      if (cache) {
        mkdirSync(cache, {recursive: true});
        const staging = mkdtempSync(join(cache,'building-'));
        try {
          const copy = join(staging,'PickerHost.app');
          cpSync(products,copy,{recursive:true});
          run('codesign',['--force','--sign','-',copy]);
          try { renameSync(staging,join(cache,cacheKey)); }
          catch (error) { if (!existsSync(cached)) throw error; }
        } finally { rmSync(staging,{recursive:true,force:true}); }
      }
    }
    const helpers = join(app, 'Contents/Helpers');
    mkdirSync(helpers, {recursive: true});
    const bundle = join(helpers, 'PickerHost.app');
    if (existsSync(bundle)) rmSync(bundle, {recursive: true});
    cpSync(products, bundle, {recursive: true});
    const resources = join(bundle, 'Contents/Resources');
    writeFileSync(join(resources, 'Source.txt'),
      'Tinycast Picker Host, AGPL-3.0-or-later\nhttps://github.com/clozach/tinycast/tree/' + revision +
      '\nBuild recipe and modifications: https://github.com/clozach/UniMagic/tree/v' +
      readFileSync(new URL('../VERSION', import.meta.url), 'utf8').trim() + '/macos/picker-host\n');
    run('codesign', ['--force', '--sign', identity, bundle]);
  } finally {
    rmSync(work, {recursive: true, force: true});
  }
}
