/**
 * Actions a glyph offers, shared by its grid tile and its detail screen. Pasting or copying
 * the glyph is a pick and teaches; copying a code point or escape is not, as in Obsidian.
 */
import { Action, ActionPanel, Clipboard, Icon, Toast, closeMainWindow, showHUD, showToast } from "@raycast/api";
import { aliasesFor, type CorpusRecord, type IndexBundle } from "../../core";
import { escapes, hexList } from "../../core/encodings";
import { skinVariants } from "../../core/glyphs";
import { GlyphDetail } from "./detail";
import { forgetWord, learnedData, rememberPick, useLearning } from "./learning";
import { TeachForm } from "./teach-form";
import { TonePicker } from "./tone-picker";
import { useDefaultTone } from "./tone-state";
import { toned } from "./tones";
import { BrowseActions } from "./category-browser";
import { recordHistory } from "./personalization";
import type { DesktopBrowse, DesktopRecord } from "../shared/desktop-browse";
import type { ReactNode } from "react";

// Closing first: with no app to return to, Tinycast's ⌘V would land in the palette's own search.
export async function pasteGlyph(record: DesktopRecord, glyph: string, query: string): Promise<void> {
  await closeMainWindow();
  await Clipboard.paste(glyph);
  rememberPick(record, query);
  await recordHistory(record, glyph, "insert");
}

/**
 * ⌘↵ / ⌘-click: paste and keep the picker up for the next glyph. `keepWindowOpen` is a
 * Tinycast extension to `Clipboard.paste`; it posts ⌘V to the app you came from without
 * activating it, so nothing lands in the picker's own search.
 */
export async function pasteGlyphKeepingOpen(record: DesktopRecord, glyph: string, query: string): Promise<void> {
  const paste = Clipboard.paste as (content: string, options: { keepWindowOpen: boolean }) => Promise<void>;
  await paste(glyph, { keepWindowOpen: true });
  rememberPick(record, query);
  await recordHistory(record, glyph, "insert");
  await showToast({ style: Toast.Style.Success, title: `Pasted ${glyph}` });
}

export async function copyGlyph(record: DesktopRecord, glyph: string, query: string): Promise<void> {
  await Clipboard.copy(glyph);
  rememberPick(record, query);
  await recordHistory(record, glyph, "copy");
  await closeMainWindow();
  await showHUD(`Copied ${glyph}`);
}

/** Copying a code point or escape is not a pick: the picker stays open, as in Obsidian. */
export async function copyValue(value: string): Promise<void> {
  await Clipboard.copy(value);
  await showToast({ style: Toast.Style.Success, title: `Copied ${value}` });
}

export interface GlyphProps {
  record: DesktopRecord;
  index: IndexBundle;
  query: string;
  model?: DesktopBrowse;
  earlier?: ReactNode;
}

/** ⌃⌘Space is also the picker's own hotkey: Tinycast hands its second press to this action. */
export function PickSection(props: GlyphProps) {
  const { record, query } = props;
  const tone = useDefaultTone();
  const glyph = record.browse?.exact ? record.symbol : toned(record, tone);
  const base = { ...record, symbol: props.index.byId.get(record.hexseq)?.symbol ?? record.symbol };
  const variants = skinVariants(base);
  return (
    <ActionPanel.Section>
      <Action
        title={`Paste ${record.name}`}
        icon={Icon.Clipboard}
        onAction={() => pasteGlyph(record, glyph, query)}
      />
      <Action
        title={`Paste ${glyph} and Keep Open`}
        icon={Icon.Clipboard}
        shortcut={{ modifiers: ["cmd"], key: "return" }}
        onAction={() => pasteGlyphKeepingOpen(record, glyph, query)}
      />
      <Action
        title={`Copy ${glyph}`}
        icon={Icon.CopyClipboard}
        shortcut={{ modifiers: ["cmd", "shift"], key: "return" }}
        onAction={() => copyGlyph(record, glyph, query)}
      />
      {variants.length > 1 && (
        <Action.Push
          title={`Skin Tones  ${variants.join(" ")}`}
          icon={Icon.Person}
          shortcut={{ modifiers: ["cmd", "ctrl"], key: "space" }}
          target={<TonePicker {...props} record={base} />}
        />
      )}
    </ActionPanel.Section>
  );
}

export function CopyAsSection({ record }: GlyphProps) {
  const codepoints = hexList(record.symbol).join(" ");
  const entity = record.entities[0];
  return (
    <ActionPanel.Section title="Copy As">
      <Action
        title={`Copy Code Point ${codepoints}`}
        icon={Icon.Hashtag}
        shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
        onAction={() => copyValue(codepoints)}
      />
      {entity && (
        <Action
          title={`Copy HTML Entity &${entity};`}
          icon={Icon.Code}
          shortcut={{ modifiers: ["cmd", "opt"], key: "c" }}
          onAction={() => copyValue(`&${entity};`)}
        />
      )}
      <Action
        title={`Copy JS Escape ${escapes(record.symbol, record.name).js}`}
        icon={Icon.Code}
        shortcut={{ modifiers: ["cmd", "ctrl"], key: "c" }}
        onAction={() => copyValue(escapes(record.symbol, record.name).js)}
      />
    </ActionPanel.Section>
  );
}

export function LearningSection({ record }: GlyphProps) {
  const shared = useLearning();
  const words = aliasesFor(learnedData(shared), record.hexseq);
  if (shared.kind !== "ready") return null;
  return (
    <ActionPanel.Section title="Your Words">
      <Action.Push
        title="Teach It a Word…"
        icon={Icon.Plus}
        shortcut={{ modifiers: ["cmd"], key: "t" }}
        target={<TeachForm record={record} />}
      />
      {words.length > 0 && (
        <ActionPanel.Submenu title="Forget a Word" icon={Icon.Trash} shortcut={{ modifiers: ["ctrl"], key: "x" }}>
          {words.map((word) => (
            <Action
              key={word.term}
              title={`Forget “${word.term}”`}
              style={Action.Style.Destructive}
              onAction={() => forgetWord(record, word.term)}
            />
          ))}
        </ActionPanel.Submenu>
      )}
    </ActionPanel.Section>
  );
}

/** The tile's panel: pick, open details, the three power copies, and teaching. */
export function GlyphActions(props: GlyphProps) {
  return (
    <ActionPanel>
      <PickSection {...props} />
      <ActionPanel.Section>
        <Action.Push
          title="Show Details"
          icon={Icon.Info}
          shortcut={{ modifiers: ["cmd"], key: "i" }}
          target={<GlyphDetail {...props} />}
        />
      </ActionPanel.Section>
      <CopyAsSection {...props} />
      <BrowseActions {...props} />
      {props.earlier}
      <LearningSection {...props} />
    </ActionPanel>
  );
}
