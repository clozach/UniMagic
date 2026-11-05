import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync } from 'node:fs';
import { join } from 'node:path';

/** Public release builds never acquire a machine-local publishing capability. */
export function configureMaintainer(root, app) {
  if (process.env.UNIMAGIC_RELEASE_BUILD === '1' || process.env.UNIMAGIC_MAINTAINER === '0') return;
  let canonical = false;
  try {
    const git = args => execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    canonical = root === join(git(['rev-parse', '--show-toplevel']), 'projects/unimagic/src')
      && ['git@github.com:clozach/amaanah.git', 'https://github.com/clozach/amaanah.git'].includes(git(['remote', 'get-url', 'origin']));
  } catch { /* Ordinary portable source is not required to be a Git checkout. */ }
  if (!canonical && process.env.UNIMAGIC_MAINTAINER !== '1') return;
  const helper = join(root, 'tools/publisher.sh');
  if (!existsSync(helper) || lstatSync(helper).isSymbolicLink()) throw Error('Maintainer publishing needs the local regular helper.');
  const output = execFileSync('/bin/bash', [helper, 'identity'], { encoding: 'utf8' }).trim();
  const fingerprint = JSON.parse(output.split('\n').at(-1)).fingerprint;
  if (!/^[a-f0-9]{64}$/.test(fingerprint)) throw Error('Maintainer source identity unavailable.');
  const info = join(app, 'Contents/Info.plist');
  for (const [key, type, value] of [
    ['UniMagicContentFingerprint', '-string', fingerprint],
    ['UniMagicPublisherEnabled', '-bool', 'YES'],
    ['UniMagicPublisherTool', '-string', helper],
    ['UniMagicMaintainerUpdateFeed', '-string', 'https://api.github.com/repos/clozach/UniMagic/releases/latest'],
  ]) execFileSync('plutil', ['-insert', key, type, value, info]);
}
