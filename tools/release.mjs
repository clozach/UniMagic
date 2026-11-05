#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mappedInput } from './source-layout.mjs';
import { releaseBuild, releasePaths } from './release-layout.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);
const run = (command, args, env = {}) => execFileSync(command, args, { stdio: 'inherit', env: { ...process.env, ...env } });
const text = (command, args) => execFileSync(command, args, { encoding: 'utf8' }).trim();
const version = readFileSync('VERSION', 'utf8').trim();
if (!/^\d+\.\d+\.\d+$/.test(version)) throw Error('VERSION must contain a semantic release number.');
const build = releaseBuild(version, process.env.BUILD_NUMBER);
const releaseFolder = resolve('.build/releases');
mkdirSync(releaseFolder, { recursive: true });
const { app, archiveApp, archive } = releasePaths(releaseFolder, version, process.arch);
const identities = text('security', ['find-identity', '-v', '-p', 'codesigning']);
const identity = process.env.SIGN_IDENTITY ?? identities.match(/([A-F0-9]{40}) "Apple Development:/)?.[1];
if (!identity || identity === '-') throw Error('A certificate-backed signing identity is required for a public updateable release.');
const fingerprintReply = text('/bin/bash', ['tools/publisher.sh', 'identity']);
const fingerprint = JSON.parse(fingerprintReply.split('\n').at(-1)).fingerprint;
if (!/^[a-f0-9]{64}$/.test(fingerprint)) throw Error('Content identity is unavailable.');
const feed = process.env.RELEASE_KIT_UPDATE_FEED ?? 'https://api.github.com/repos/clozach/UniMagic/releases/latest';

run('pnpm', ['run', 'build:tinycast']);
const payloadFolder = resolve('.build/ios-payload');
run(process.execPath, ['ios/package-payload.mjs', payloadFolder], { BUILD_VERSION: version, BUILD_NUMBER: build });
const manifest = JSON.parse(readFileSync(join(payloadFolder, 'manifest.json'), 'utf8'));
if (manifest.version !== version || manifest.build !== build || manifest.product !== 'com.clozach.unimagic') {
  throw Error('iOS payload identity/version does not match this release.');
}
run(process.execPath, ['macos/build.mjs'], { BUILD_VERSION: version, BUILD_NUMBER: build, SIGN_IDENTITY: identity, UNIMAGIC_RELEASE_BUILD: '1', UNIMAGIC_MAINTAINER: '0' });
rmSync(app, { recursive: true, force: true });
cpSync('macos/build/UniMagic.app', app, { recursive: true });
const resources = join(app, 'Contents/Resources');
const payload = join(resources, 'iOS'); mkdirSync(payload, { recursive: true });
for (const name of ['UniMagic-iOS.unsigned.zip', 'manifest.json']) {
  if (!existsSync(join(payloadFolder, name))) throw Error(`Missing unsigned iOS payload: ${name}`);
  cpSync(join(payloadFolder, name), join(payload, name));
}
for (const part of ['keeper', 'signing']) {
  const input = mappedInput(root, `tools/paired-mac/${part}`, `../../iphone-agent-alerts/src/${part}`);
  if (!existsSync(input)) throw Error(`Missing portable paired-Mac ${part} tools.`);
  cpSync(input, join(resources, 'paired-mac', part), { recursive: true });
}
const info = join(app, 'Contents/Info.plist');
for (const [key, value] of Object.entries({ UniMagicContentFingerprint: fingerprint, UniMagicUpdateFeed: feed })) {
  run('plutil', ['-insert', key, '-string', value, info]);
}
run('codesign', ['--force', '--sign', identity, app]);
run('codesign', ['--verify', '--deep', '--strict', app]);
rmSync(archive, { force: true });
rmSync(dirname(archiveApp), { recursive: true, force: true });
mkdirSync(dirname(archiveApp), { recursive: true });
cpSync(app, archiveApp, { recursive: true });
run('ditto', ['-c', '-k', '--norsrc', '--keepParent', archiveApp, archive]);
const hash = createHash('sha256').update(readFileSync(archive)).digest('hex');
writeFileSync(join(releaseFolder, 'SHA256SUMS'), `${hash}  ${archive.split('/').at(-1)}\n`);
console.log(JSON.stringify({ version, build, fingerprint, app, archive, sha256: hash }));
