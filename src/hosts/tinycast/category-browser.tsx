/** Catalogue settings and context previews use native navigation; Escape returns intact. */
import { Action, ActionPanel, Grid, Icon, List } from "@raycast/api";
import { useEffect, useMemo, useRef, useState } from "react";
import type { IndexBundle } from "../../core/search";
import { categoryByID, categoryDisplayTitle, categorySourceLabel, historyRecord, viewKey, type DesktopBrowse, type DesktopRecord } from "../shared/desktop-browse";
import { GlyphActions, type GlyphProps } from "./actions";
import { usePersonalization } from "./personalization";
import { tileText } from "./browse";
import { useDefaultTone } from "./tone-state";
import { frequentlyUsed } from "../../core/learning";
import { recordFor } from "../../core/glyphs";
import { learnedData, useLearning } from "./learning";

const PAGE = 200;
export function categoryTitle(model: DesktopBrowse, id: string): string {
  const category = categoryByID.get(id)!;
  return categoryDisplayTitle(category);
}
export function categoryIcon(model: DesktopBrowse, id: string) {
  const exemplar = model.exemplar(id);
  return exemplar.kind === "custom-font" ? defaultCategoryIcon(id) : exemplar.symbol;
}
function defaultCategoryIcon(id: string) {
  return categoryByID.get(id)?.defaultExemplar.kind === "custom-font" ? { source: { light: `categories/${id.replace(":", "-")}-light.png`, dark: `categories/${id.replace(":", "-")}-dark.png` } } : undefined;
}
export function CategorySettings({ model, index }: { model: DesktopBrowse; index: IndexBundle }) {
  usePersonalization(model);
  return <List searchBarPlaceholder="Find a category or Unicode block" filtering>
    {model.categories().map(category => <List.Item key={category.id} id={category.id}
      title={category.title} icon={categoryIcon(model, category.id)} subtitle={category.source.kind === "utility" ? undefined : `${category.memberCount.toLocaleString()} glyphs${categorySourceLabel(category) ? " · " + categorySourceLabel(category) : ""}`}
      accessories={[{ text: model.enabled(category.id) ? "Shown" : "Hidden" }]}
      actions={<ActionPanel>
        <Action title={model.enabled(category.id) ? "Hide Category" : "Show Category"} icon={Icon.Checkmark}
          onAction={() => model.setEnabled(category.id, !model.enabled(category.id))} />
        <Action.Push title="Browse Category" target={<CategoryGrid model={model} index={index} categoryID={category.id} />} />
        {model.preferences.exemplarOverrides[category.id] && <Action
          title={`Reset Default ${category.defaultExemplar.kind === "custom-font" ? "Exemplar" : category.defaultExemplar.symbol}`}
          icon={defaultCategoryIcon(category.id)}
          onAction={() => model.setExemplar(category.id, null)} />}
      </ActionPanel>} />)}
  </List>;
}

/** Native Grid pagination appends batches, preserving the grid and scroll position. */
export function CategoryGrid({ model, index, categoryID, focus }: {
  model: DesktopBrowse; index: IndexBundle; categoryID: string; focus?: DesktopRecord;
}) {
  usePersonalization(model);
  const tone = useDefaultTone();
  const learned = useLearning();
  const [query, setQuery] = useState("");
  const members = useMemo(() => model.members(categoryID), [model, categoryID]);
  const start = focus ? members.findIndex(r => viewKey(r) === viewKey(focus)) : -1;
  const offset = Math.max(0, Math.floor(start / PAGE) * PAGE);
  const [limit, setLimit] = useState(PAGE);
  const [recent, setRecent] = useState<DesktopRecord[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const inFlight = useRef(false);
  const isRecent = categoryID === "utility:recents";
  const loadHistory = async (after?: string) => {
    if (inFlight.current) return; inFlight.current = true; setLoading(true);
    try { const page = await model.history(after); setRecent(previous => after ? [...previous, ...page.events.map(e => historyRecord(e, index))] : page.events.map(e => historyRecord(e, index))); setCursor(page.nextCursor); }
    finally { inFlight.current = false; setLoading(false); }
  };
  useEffect(() => {
    if (!isRecent) return;
    void loadHistory();
    return model.subscribe(() => void loadHistory());
  }, [model, isRecent]);
  const frequent = frequentlyUsed(learnedData(learned), 25).flatMap(id => recordFor(index, id) ?? []);
  const records = (isRecent ? recent : categoryID === "utility:frequent" ? frequent : members).filter(r => !query || `${r.name} ${r.symbol} ${r.hexseq}`.toLowerCase().includes(query.toLowerCase()));
  const shown = isRecent ? records : records.slice(query ? 0 : offset, (query ? 0 : offset) + limit);
  const hasEarlier = !isRecent && !query && offset > 0;
  const earlier = <Action.Push title="Earlier Glyphs" icon={Icon.ArrowUp}
    target={<CategoryGrid model={model} index={index} categoryID={categoryID} focus={members[Math.max(0, offset - PAGE)]} />} />;
  return <Grid columns={8} inset={Grid.Inset.Medium} filtering={false} isLoading={loading}
    navigationTitle={categoryByID.has(categoryID) ? categoryDisplayTitle(categoryByID.get(categoryID)!) : undefined} selectedItemId={focus ? viewKey(focus) : undefined}
    onSearchTextChange={value => { setQuery(value); setLimit(PAGE); }} searchBarPlaceholder="Browse this category · Esc returns"
    actions={hasEarlier ? <ActionPanel>{earlier}</ActionPanel> : undefined}
    pagination={{ pageSize: PAGE, hasMore: isRecent ? cursor !== null : records.length > (query ? 0 : offset) + limit,
      onLoadMore: () => { if (isRecent && cursor) void loadHistory(cursor); else setLimit(n => n + PAGE); } }}>
    {shown.map(record => <Grid.Item key={viewKey(record)} id={viewKey(record)}
      content={{ value: tileText(record, tone), tooltip: record.name }}
      actions={<GlyphActions record={record} index={index} query="" model={model} earlier={hasEarlier ? earlier : undefined} />} />)}
  </Grid>;
}

function ExemplarDestination({ record, model }: { record: DesktopRecord; model: DesktopBrowse }) {
  usePersonalization(model);
  const contexts = model.contexts(record);
  const destinations = contexts.length ? contexts.map(c => c.category) : model.categories().filter(c => c.source.kind !== "utility");
  return <List searchBarPlaceholder="Use this glyph for which category?">
    {destinations.map(category => <List.Item
      key={category.id} title={categoryTitle(model, category.id)} icon={categoryIcon(model, category.id)}
      actions={<ActionPanel><Action title={`Use ${record.symbol} as Exemplar`}
        onAction={() => model.setExemplar(category.id, record.symbol)} /></ActionPanel>} />)}
  </List>;
}

export function BrowseActions(props: GlyphProps) {
  const { model, record, index } = props;
  usePersonalization(model);
  if (!model) return null;
  const contexts = model.contexts(record);
  const current = categoryByID.get(record.browse?.origin?.categoryID ?? "");
  const destination = current ?? (contexts.length === 1 ? contexts[0].category : undefined);
  return <ActionPanel.Section title="Categories">
    {destination ? model.preferences.exemplarOverrides[destination.id]
      ? <Action title={`Reset Default ${destination.defaultExemplar.kind === "custom-font" ? "Exemplar" : destination.defaultExemplar.symbol}`}
          icon={defaultCategoryIcon(destination.id)}
          onAction={() => model.setExemplar(destination.id, null)} />
      : <Action title={`Use ${record.symbol} as ${destination.title} Exemplar`} onAction={() => model.setExemplar(destination.id, record.symbol)} />
      : <Action.Push title={`Use ${record.symbol} as Category Exemplar…`} target={<ExemplarDestination record={record} model={model} />} />}
    {contexts.map(({ category, record: member }) => <Action.Push key={category.id} title={`Show in ${categoryDisplayTitle(category)}`}
      icon={Icon.ArrowRight} target={<CategoryGrid model={model} index={index} categoryID={category.id} focus={member} />} />)}
    <Action.Push title="Category Settings…" icon={Icon.Gear} target={<CategorySettings model={model} index={index} />} />
  </ActionPanel.Section>;
}
