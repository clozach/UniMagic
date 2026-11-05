import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';

const statePath = 'support/PowWorm/state.json';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const changed = detail => Error('Saved data changed during installation; backups retained, never overwrite newer data (' + detail + ')');

// Compare JSON formatting without converting numbers to IEEE doubles. Numeric
// spelling stays exact: even 1 -> 1.0 requires review. Duplicate decoded keys
// are ambiguous and refused. Tags distinguish arrays/objects/strings/numbers.
function jsonContent(bytes) {
  const text = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes);
  const string = /"(?:[^"\\\u0000-\u001f]|\\["\\/bfnrt]|\\u[0-9a-fA-F]{4})*"/y;
  const scalar = /(?:-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)/y;
  let position = 0;
  const space = () => { while (/[\t\n\r ]/.test(text[position] ?? '')) position++; };
  const takeString = () => {
    string.lastIndex = position;
    const match = string.exec(text);
    if (!match) throw Error('Invalid JSON string');
    position = string.lastIndex;
    return JSON.parse(match[0]);
  };
  function value(depth = 0) {
    if (depth > 128) throw Error('JSON nesting exceeds comparison limit');
    space();
    const first = text[position];
    if (first === '"') return ['string', takeString()];
    if (first === '{' || first === '[') {
      const object = first === '{', close = object ? '}' : ']';
      const entries = [], keys = new Set();
      position++; space();
      if (text[position] !== close) for (;;) {
        space();
        if (object) {
          const key = takeString();
          if (keys.has(key)) throw Error('Duplicate JSON key');
          keys.add(key); space();
          if (text[position++] !== ':') throw Error('Missing JSON colon');
          entries.push([key, value(depth + 1)]);
        } else entries.push(value(depth + 1));
        space();
        if (text[position] === close) break;
        if (text[position++] !== ',') throw Error('Missing JSON separator');
      }
      position++;
      if (object) entries.sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
      return [object ? 'object' : 'array', entries];
    }
    scalar.lastIndex = position;
    const match = scalar.exec(text);
    if (!match) throw Error('Invalid JSON value');
    position = scalar.lastIndex;
    return ['scalar', match[0]];
  }
  const result = value(); space();
  if (position !== text.length) throw Error('Trailing JSON data');
  return JSON.stringify(result);
}

/** Read-only comparison of retained snapshots; never restores or rewrites data. */
export function compareSavedData(before, after, beforeDirectory, afterDirectory) {
  const paths = Object.keys(before).sort();
  if (JSON.stringify(paths) !== JSON.stringify(Object.keys(after).sort())) throw changed('saved file inventory differs');
  return paths.map(path => {
    const result = {path, beforeSHA256: before[path], afterSHA256: after[path], comparison: 'byte-identical'};
    if (before[path] === after[path]) return result;
    if (path !== statePath) throw changed(path);
    let left, right;
    try {
      const a = readFileSync(join(beforeDirectory, path)), b = readFileSync(join(afterDirectory, path));
      if (hash(a) !== before[path] || hash(b) !== after[path]) throw Error('Snapshot changed after hashing');
      left = jsonContent(a); right = jsonContent(b);
    } catch { throw changed(path + ': malformed, ambiguous or changed snapshot'); }
    if (left !== right) throw changed(path + ': JSON content differs');
    return {...result, comparison: 'json-formatting-only'};
  });
}
