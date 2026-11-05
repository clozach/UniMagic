import test from 'node:test';
import assert from 'node:assert/strict';
import { releaseBuild, releasePaths } from '../release-layout.mjs';

test('default release builds advance across patch, minor and major versions', () => {
  const builds = ['0.9.999', '1.0.0', '1.0.1', '1.1.0', '2.0.0'].map(v => Number(releaseBuild(v)));
  assert.ok(builds.every((b, i) => i === 0 || b > builds[i - 1]));
  assert.throws(() => releaseBuild('1.1000.0'));
  assert.throws(() => releaseBuild('1.0.0', '0'));
});

test('public ZIP stage has the exact bundle name accepted by both updaters', () => {
  const result = releasePaths('/release', '1.0.0', 'arm64');
  assert.equal(result.archiveApp.split('/').at(-1), 'UniMagic.app');
  assert.equal(result.archive.split('/').at(-1), 'UniMagic-1.0.0-macOS-arm64.zip');
  assert.throws(() => releasePaths('/release', '1.0.0', 'x64'));
});
