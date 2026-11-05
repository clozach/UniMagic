/**
 * The detail screen's text: the glyph large, its name, its class line, each code point named,
 * and its Twins and Related, which need the wide pane. Pure, so the suite checks it.
 */
import type { CorpusRecord, IndexBundle } from "../../core";
import { codePoints } from "../../core/encodings";
import { componentName } from "../../core/glyphs";
import { tileText } from "./browse";

/** Backslash-escape ASCII punctuation so a glyph like `*` or `#` shows as itself, not as syntax. */
export function escapeMarkdown(text: string): string {
  return text.replace(/[\\`*_{}[\]()#+\-.!|<>~]/g, (ch) => `\\${ch}`);
}

export function classLine(record: CorpusRecord): string {
  return [record.block, record.set, record.script, record.age ? `Unicode ${record.age}` : null]
    .filter(Boolean)
    .join(" · ");
}

/** One line per code point, so a ZWJ sequence shows the parts it is built from. */
export function componentLines(record: CorpusRecord, index: IndexBundle): string[] {
  return codePoints(record.symbol).map((cp) => {
    const hex = `U+${cp.toString(16).toUpperCase().padStart(4, "0")}`;
    const name = componentName(cp, index);
    return name ? `\`${hex}\` ${escapeMarkdown(name)}` : `\`${hex}\``;
  });
}

function records(hexseqs: string[], index: IndexBundle): CorpusRecord[] {
  return hexseqs.map((h) => index.byId.get(h)).filter((r): r is CorpusRecord => !!r);
}

export function detailMarkdown(record: CorpusRecord, index: IndexBundle): string {
  const lines = [`# ${escapeMarkdown(tileText(record))}`, "", `## ${escapeMarkdown(record.name)}`];
  const klass = classLine(record);
  if (klass) lines.push("", escapeMarkdown(klass));
  lines.push("", "### Code points", "", ...componentLines(record, index).map((line) => `- ${line}`));
  const twins = records(record.twins, index);
  if (twins.length) {
    lines.push("", "### Twins — could be mistaken for it", "");
    lines.push(...twins.map((r) => `- ${escapeMarkdown(tileText(r))}  ${escapeMarkdown(r.name)}`));
  }
  const related = records(record.related, index);
  if (related.length) {
    lines.push("", "### Related — same idea, different look", "", related.map((r) => r.symbol).join("  "));
  }
  if (record.annotations?.length) {
    lines.push("", "### Notes", "", ...record.annotations.map((note) => `- ${escapeMarkdown(note)}`));
  }
  return lines.join("\n");
}
