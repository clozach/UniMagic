import { join } from 'node:path';

export function releaseBuild(version, override) {
  const parts = version.split('.').map(Number);
  if (parts.length !== 3 || parts.some(n => !Number.isSafeInteger(n) || n < 0 || n > 999)) {
    throw Error('Release version components must be integers from 0 to 999.');
  }
  const build = override ?? String(parts[0] * 1_000_000 + parts[1] * 1_000 + parts[2] + 1);
  if (!/^[1-9][0-9]*$/.test(build) || !Number.isSafeInteger(Number(build))) throw Error('BUILD_NUMBER must be a positive integer.');
  return build;
}

export function releasePaths(folder, version, arch) {
  if (arch !== 'arm64') throw Error('This release target currently supports Apple Silicon Macs.');
  return {
    app: join(folder, `UniMagic-${version}.app`),
    archiveApp: join(folder, `archive-${version}`, 'UniMagic.app'),
    archive: join(folder, `UniMagic-${version}-macOS-${arch}.zip`),
  };
}
