import { execFileSync } from 'node:child_process';
import { cpSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Ship the exact local adaptations, including preview builds before a release tag exists.
export function sealHostSource(app, identity) {
  const macos = fileURLToPath(new URL('.', import.meta.url));
  const helper = join(app, 'Contents/Helpers/PickerHost.app');
  const resources = join(helper, 'Contents/Resources');
  const source = join(resources, 'CorrespondingSource/macos');
  mkdirSync(source, { recursive: true });
  cpSync(join(macos, '../VERSION'), join(resources, 'CorrespondingSource/VERSION'));
  cpSync(join(macos, 'picker-host'), join(source, 'picker-host'), { recursive: true });
  for (const script of ['build-picker-host.mjs', 'host-source-notice.mjs']) {
    cpSync(join(macos, script), join(source, script));
  }
  const revision = readFileSync(join(source, 'picker-host/TINYCAST_REVISION'), 'utf8').trim();
  writeFileSync(join(resources, 'Source.txt'), [
    'Tinycast Picker Host — AGPL-3.0-or-later',
    'The exact helper entry point, adaptation patch, XcodeGen project, build script and license are beside this file in CorrespondingSource/macos.',
    'Apply those adaptations to the unmodified Tinycast revision below.',
    'https://github.com/clozach/tinycast/tree/' + revision,
    '',
  ].join('\n'));
  execFileSync('codesign', ['--force', '--sign', identity, helper], { stdio: 'inherit' });
}
