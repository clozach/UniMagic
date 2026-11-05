/**
 * Tier 2: everything Unimagic knows about one glyph. The text sits left, the technical rows
 * in the sidebar; every value shown is also an action, so nothing is look-but-don't-touch.
 */
import { Action, ActionPanel, Color, Detail, Icon } from "@raycast/api";
import { aliasesFor, type CorpusRecord } from "../../core";
import { escapes, hexList, utf16Units, utf8Bytes } from "../../core/encodings";
import { ESCAPE_LABELS, skinVariants } from "../../core/glyphs";
import { CopyAsSection, LearningSection, PickSection, copyValue, type GlyphProps } from "./actions";
import { classLine, detailMarkdown } from "./detail-text";
import { learnedData, useLearning } from "./learning";
import { BrowseActions } from "./category-browser";
import { historyDescription } from "../shared/desktop-browse";

const BUILTIN_WORDS_SHOWN = 12;

function builtinWords(record: CorpusRecord): string[] {
  return [...new Set(record.keywords.map((k) => k.token))].slice(0, BUILTIN_WORDS_SHOWN);
}

function related(hexseqs: string[], props: GlyphProps): CorpusRecord[] {
  return hexseqs.map((h) => props.index.byId.get(h)).filter((r): r is CorpusRecord => !!r);
}

function Metadata(props: GlyphProps) {
  const { record } = props;
  const words = aliasesFor(learnedData(useLearning()), record.hexseq);
  const esc = escapes(record.symbol, record.name);
  const variants = skinVariants({ ...record, symbol: props.index.byId.get(record.hexseq)?.symbol ?? record.symbol });
  const first = record.hexseq.split(" ")[0];
  return (
    <Detail.Metadata>
      <Detail.Metadata.TagList title="Your words">
        {words.length === 0 ? (
          <Detail.Metadata.TagList.Item text="none yet — ⌘T teaches one" color={Color.SecondaryText} />
        ) : (
          words.map((w) => (
            <Detail.Metadata.TagList.Item
              key={w.term}
              text={w.type === "learned" ? w.term : `${w.term} (provisional)`}
              color={w.type === "learned" ? Color.Green : Color.Orange}
            />
          ))
        )}
      </Detail.Metadata.TagList>
      <Detail.Metadata.TagList title="Built-in words">
        {builtinWords(record).map((word) => (
          <Detail.Metadata.TagList.Item key={word} text={word} color={Color.SecondaryText} />
        ))}
      </Detail.Metadata.TagList>
      <Detail.Metadata.Separator />
      {historyDescription(record) && <Detail.Metadata.Label title="History" text={historyDescription(record)} />}
      <Detail.Metadata.Label title="Code points" text={hexList(record.symbol).join(" ")} />
      <Detail.Metadata.Label title="UTF-8" text={utf8Bytes(record.symbol)} />
      <Detail.Metadata.Label title="UTF-16" text={utf16Units(record.symbol)} />
      {ESCAPE_LABELS.filter(([key]) => esc[key]).map(([key, label]) => (
        <Detail.Metadata.Label key={key} title={label} text={esc[key]} />
      ))}
      {record.entities.length > 0 && (
        <Detail.Metadata.TagList title="HTML entities">
          {record.entities.map((e) => (
            <Detail.Metadata.TagList.Item key={e} text={`&${e};`} />
          ))}
        </Detail.Metadata.TagList>
      )}
      <Detail.Metadata.Label title="Class" text={classLine(record) || "–"} />
      <Detail.Metadata.Separator />
      {variants.length > 1 && (
        <Detail.Metadata.TagList title="Variants">
          {variants.map((v) => (
            <Detail.Metadata.TagList.Item key={v} text={v} />
          ))}
        </Detail.Metadata.TagList>
      )}
      <Detail.Metadata.Separator />
      <Detail.Metadata.Link
        title="Look it up"
        text="Wikipedia"
        target={`https://en.wikipedia.org/w/index.php?search=${encodeURIComponent(record.name)}`}
      />
      <Detail.Metadata.Link title="" text="codepoints.net" target={`https://codepoints.net/U+${first}`} />
      <Detail.Metadata.Link
        title=""
        text="unicode.org"
        target={`https://util.unicode.org/UnicodeJsps/character.jsp?a=${first}`}
      />
    </Detail.Metadata>
  );
}

function NavigateSubmenu({ title, records, props }: { title: string; records: CorpusRecord[]; props: GlyphProps }) {
  if (records.length === 0) return null;
  return (
    <ActionPanel.Submenu title={title} icon={Icon.ArrowRight}>
      {records.map((r) => (
        <Action.Push
          key={r.hexseq}
          title={`${r.symbol}  ${r.name}`}
          target={<GlyphDetail {...props} record={r} />}
        />
      ))}
    </ActionPanel.Submenu>
  );
}

function DetailActions(props: GlyphProps) {
  const { record } = props;
  const esc = escapes(record.symbol, record.name);
  return (
    <ActionPanel>
      <PickSection {...props} />
      <CopyAsSection {...props} />
      <BrowseActions {...props} />
      {props.earlier}
      <ActionPanel.Section title="Copy Any Value">
        <Action title={`Copy UTF-8 ${utf8Bytes(record.symbol)}`} onAction={() => copyValue(utf8Bytes(record.symbol))} />
        <Action title={`Copy UTF-16 ${utf16Units(record.symbol)}`} onAction={() => copyValue(utf16Units(record.symbol))} />
        <ActionPanel.Submenu title="Copy Escape" icon={Icon.Code} shortcut={{ modifiers: ["cmd"], key: "e" }}>
          {ESCAPE_LABELS.filter(([key]) => esc[key]).map(([key, label]) => (
            <Action key={key} title={`${label}  ${esc[key]}`} onAction={() => copyValue(esc[key])} />
          ))}
        </ActionPanel.Submenu>
        {record.entities.slice(1).map((e) => (
          <Action key={e} title={`Copy HTML Entity &${e};`} onAction={() => copyValue(`&${e};`)} />
        ))}
        <Action title="Copy Name" onAction={() => copyValue(record.name)} />
      </ActionPanel.Section>
      <LearningSection {...props} />
      <ActionPanel.Section title="Go To">
        <NavigateSubmenu title="Twins" records={related(record.twins, props)} props={props} />
        <NavigateSubmenu title="Related" records={related(record.related, props)} props={props} />
        <Action.OpenInBrowser
          title="Open on codepoints.net"
          url={`https://codepoints.net/U+${record.hexseq.split(" ")[0]}`}
        />
      </ActionPanel.Section>
    </ActionPanel>
  );
}

export function GlyphDetail(props: GlyphProps) {
  return (
    <Detail
      navigationTitle={props.record.name}
      markdown={detailMarkdown(props.record, props.index)}
      metadata={<Metadata {...props} />}
      actions={<DetailActions {...props} />}
    />
  );
}
