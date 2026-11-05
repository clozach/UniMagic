import { createHash } from 'node:crypto';

/** Public build input contains fixed catalogue facts, never observed usage. */
export function publicReference(bytes) {
  const raw = JSON.parse(bytes.toString('utf8'));
  const categories = raw.categories.map(c => ({
    id: c.id, name: c.name,
    index_icon: { font_character: c.index_icon.font_character },
    observed: c.observed.map(e => ({ glyph: e.glyph, accessibility_name: e.accessibility_name ?? null })),
    source_positions: c.source_positions.map(e => ({ glyph: e.glyph })),
  }));
  const result = {
    schema_version: 1, font_sha256: raw.font_sha256,
    source_sha256: raw.source_sha256 ?? createHash('sha256').update(bytes).digest('hex'), categories,
  };
  requirePublicReference(result);
  return result;
}

export function requirePublicReference(reference) {
  const keys = Object.keys(reference).sort().join(',');
  if (keys !== 'categories,font_sha256,schema_version,source_sha256'
      || reference.schema_version !== 1 || !Array.isArray(reference.categories)) {
    throw Error('Public reference contains unsupported metadata or dynamic history.');
  }
  for (const c of reference.categories) {
    if (Object.keys(c).sort().join(',') !== 'id,index_icon,name,observed,source_positions'
        || typeof c.id !== 'string' || !c.id.startsWith('Category-')
        || /recent|frequent|history/i.test(c.id + c.name)
        || !Array.isArray(c.observed) || !Array.isArray(c.source_positions)) {
      throw Error('Public reference contains a dynamic or unsupported category.');
    }
    if (Object.keys(c.index_icon).join(',') !== 'font_character') throw Error('Unexpected icon metadata.');
    for (const e of c.observed) {
      if (Object.keys(e).sort().join(',') !== 'accessibility_name,glyph') throw Error('Unexpected observed metadata.');
    }
    for (const e of c.source_positions) {
      if (Object.keys(e).join(',') !== 'glyph') throw Error('Unexpected source metadata.');
    }
  }
  return reference;
}
