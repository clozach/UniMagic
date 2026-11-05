import { readFileSync, readdirSync, lstatSync } from 'node:fs';
import { join, relative } from 'node:path';
import { createHash } from 'node:crypto';
import { requirePublicReference } from './reference-input.mjs';

const forbidden = [
  ['private key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
  ['GitHub credential', /\bgh[pousr]_[A-Za-z0-9_]{30,}\b/],
  ['personal absolute path', /\/Users\/c(?:\/|\b)/],
  ['copied UniChar font', /(?:^|\/)UniCharCategories\.ttf$/],
  ['personal Recents seed', /(?:^|\/)(?:RecentsSeed|recents-screenshot-seed)\.json$/],
  ['provisioning profile', /\.mobileprovision$/],
  ['device identifier', /\b0000[0-9a-f]{4}-[0-9a-f]{16}\b/i],
];

export function auditSource(root) {
  const files = [];
  function walk(folder) {
    for (const entry of readdirSync(folder, { withFileTypes: true })) {
      if (entry.name === '.git') continue;
      const path = join(folder, entry.name), name = relative(root, path).split('\\').join('/');
      if (lstatSync(path).isSymbolicLink()) throw Error(`Public source contains a symlink: ${name}`);
      if (entry.isDirectory()) { walk(path); continue; }
      const bytes = readFileSync(path);
      if (name === 'reference/unichar-inventory.json') requirePublicReference(JSON.parse(bytes.toString('utf8')));
      for (const [reason, pattern] of forbidden) {
        if (pattern.test(name) || (!bytes.includes(0) && pattern.test(bytes.toString('utf8')))) {
          throw Error(`Public source rejected (${reason}): ${name}`);
        }
      }
      files.push({ path: name, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
    }
  }
  walk(root);
  return files.sort((a, b) => a.path.localeCompare(b.path));
}
