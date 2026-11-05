/**
 * Unimagic in Tinycast (or Raycast): the picker grid. An empty query browses enabled
 * categories; typing searches the complete corpus with your own words ranked first.
 * Category scopes and native infinite scrolling retain every source occurrence.
 */
import { Action, ActionPanel, Grid, Icon, Toast, environment, getPreferenceValues, showToast } from "@raycast/api";
import { homedir, release } from "node:os";
import { useEffect, useMemo, useRef, useState } from "react";
import { search, frequentlyUsed, type IndexBundle } from "../../core";
import { recordFor } from "../../core/glyphs";
import { GlyphActions } from "./actions";
import { tileText, windowSections, type Missing } from "./browse";
import { catalogue, categoryByID, historyRecord, viewKey, type DesktopBrowse, type DesktopRecord } from "../shared/desktop-browse";
import { CategorySettings, categoryTitle, categoryIcon } from "./category-browser";
import { openPersonalization, usePersonalization } from "./personalization";
import { loadIndex } from "./corpus";
import { coverageKey, coveragePaths, readCoverage, scanCoverage } from "./coverage";
import { learnedData, openLearning, useLearning } from "./learning";
import { loadDefaultTone, useDefaultTone } from "./tone-state";
import { expandHome, type SharedData } from "./shared-store";

import { ensureMacLibrary } from "./shared-mac-store";

function dataFile(): string {
  const { dataFile } = getPreferenceValues<{ dataFile?: string }>();
  const configured = dataFile?.trim() ? expandHome(dataFile.trim(), homedir()) : undefined;
  return configured?.replace(/\\/g, "/").includes("/.obsidian/plugins/unimagic/") ? ensureMacLibrary(configured) : configured ?? ensureMacLibrary();
}

function warnIfLearningOff(launch: SharedData): void {
  if (launch.kind === "missing") {
    void showToast({
      style: Toast.Style.Failure,
      title: "Learning is off",
      message: `No UniMagic library folder at ${launch.dir}. Set the file in the extension's preferences.`,
    });
  } else if (launch.kind === "unreadable") {
    void showToast({
      style: Toast.Style.Failure,
      title: "Learned words are read-only",
      message: `${launch.file}: ${launch.reason}`,
    });
  }
}

const NOTHING_MISSING: Missing = new Set();

/** The cached answer when there is one; otherwise a background scan, reported as it ends. */
function useMissingGlyphs(index: IndexBundle | null): Missing {
  const [missing, setMissing] = useState<Missing>(NOTHING_MISSING);
  useEffect(() => {
    if (!index) return;
    const paths = coveragePaths(environment.assetsPath, environment.supportPath);
    const key = coverageKey(`${index.build} / browse:${catalogue.revision}`, release());
    const cached = readCoverage(paths.cache, key);
    if (cached) return setMissing(cached);
    let live = true;
    void showToast({ style: Toast.Style.Animated, title: "Checking which glyphs this Mac can draw…" });
    scanCoverage(paths, key).then(
      (found) => {
        if (!live) return;
        setMissing(found);
        void showToast({
          style: Toast.Style.Success,
          title: `Hid ${found.size.toLocaleString("en-US")} glyphs this Mac can't draw`,
          message: "Checked again after each macOS update.",
        });
      },
      (error: Error) => {
        if (!live) return;
        void showToast({ style: Toast.Style.Failure, title: "Couldn't check which glyphs draw", message: error.message });
      },
    );
    return () => {
      live = false;
    };
  }, [index]);
  return missing;
}

function ScopeDropdown({ model, value, onChange }: { model: DesktopBrowse | null; value: string; onChange: (id: string) => void }) {
  return <Grid.Dropdown tooltip="Browse categories" storeValue={false} value={value} onChange={onChange}>
    <Grid.Dropdown.Item value="browse" title="Browse enabled categories" />
    {model?.categories(true).map(category => <Grid.Dropdown.Item key={category.id} value={category.id} icon={categoryIcon(model, category.id)} title={categoryTitle(model, category.id)} />)}
  </Grid.Dropdown>;
}

export default function Unimagic() {
  const [file] = useState(dataFile);
  const [launch] = useState(() => openLearning(file));
  const shared = useLearning();
  const [index, setIndex] = useState<IndexBundle | null>(null);
  const [query, setQuery] = useState("");
  const [scopeKey, setScopeKey] = useState("browse");
  const [limit, setLimit] = useState(200);
  const [history, setHistory] = useState<DesktopRecord[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const historyInFlight = useRef(false);
  const model = useMemo(() => index ? openPersonalization(index, file) : null, [index, file]);
  usePersonalization(model);
  const tone = useDefaultTone();
  useEffect(() => warnIfLearningOff(launch), [launch]);
  useEffect(() => void loadDefaultTone(), []);
  useEffect(() => { const timer = setTimeout(() => setIndex(loadIndex()), 0); return () => clearTimeout(timer); }, []);
  useEffect(() => {
    if (!model) return;
    void model.initialize().then(() => model.importLegacyUsage(learnedData(launch).usage)).catch(error => showToast({ style: Toast.Style.Failure, title: "Personalization unavailable", message: String(error) }));
  }, [model]);
  const loadHistory = async (after?: string) => {
    if (!model || !index || historyInFlight.current) return;
    historyInFlight.current = true;
    setLoading(true);
    try {
      const page = await model.history(after);
      const records = page.events.map(e => historyRecord(e, index));
      setHistory(previous => after ? [...previous, ...records] : records);
      setCursor(page.nextCursor);
    } catch (error) { void showToast({ style: Toast.Style.Failure, title: "Could not read history", message: String(error) }); }
    finally { historyInFlight.current = false; setLoading(false); }
  };
  useEffect(() => {
    if (!model) return;
    void loadHistory();
    return model.subscribe(() => void loadHistory());
  }, [model]);
  useEffect(() => setLimit(200), [query, scopeKey]);
  const missing = useMissingGlyphs(index);
  const sections = useMemo((): { title: string; records: DesktopRecord[] }[] => {
    if (!index || !model) return [];
    const visible = (records: DesktopRecord[]) => records.filter(r => r.set === "Spaces" || !missing.has(r.hexseq));
    if (query.trim()) {
      let records: DesktopRecord[] = search({ index, data: learnedData(shared) }, query).map(h => h.record);
      if (scopeKey !== "browse" && scopeKey !== "utility:recents" && scopeKey !== "utility:frequent") {
        const ids = new Set(model.members(scopeKey).map(r => r.hexseq)); records = records.filter(r => ids.has(r.hexseq));
      }
      return [{ title: "Results", records: visible(records) }];
    }
    const frequent = frequentlyUsed(learnedData(shared), 25).flatMap(id => recordFor(index, id) ?? []);
    if (scopeKey === "utility:recents") return [{ title: "Recents · full history", records: history }];
    if (scopeKey === "utility:frequent") return [{ title: "Frequently used", records: visible(frequent) }];
    if (scopeKey !== "browse") return [{ title: categoryByID.get(scopeKey)?.title ?? "Category", records: visible(model.members(scopeKey)) }];
    return model.categories(true).map(category => ({ title: category.title,
      records: category.id === "utility:recents" ? history.slice(0, 20) : category.id === "utility:frequent" ? visible(frequent) : visible(model.members(category.id)) }));
  }, [index, model, query, scopeKey, shared, missing, history, model?.preferences]);
  const total = sections.reduce((n, s) => n + s.records.length, 0);
  const isHistory = scopeKey === "utility:recents" && !query.trim();
  const shown = windowSections(sections, isHistory ? { kind: "history" } : { kind: "browse", limit });
  const hasMore = isHistory ? cursor !== null : total > limit;
  return <Grid columns={8} inset={Grid.Inset.Medium} isLoading={!index || loading} filtering={false}
    onSearchTextChange={setQuery} searchBarPlaceholder="Search glyphs: a word, ->, U+2014, or paste one"
    searchBarAccessory={<ScopeDropdown model={model} value={scopeKey} onChange={setScopeKey} />}
    pagination={{ pageSize: 200, hasMore, onLoadMore: () => { if (isHistory && cursor) void loadHistory(cursor); else setLimit(n => n + 200); } }}
    actions={model && index ? <ActionPanel><Action.Push title="Category Settings…" icon={Icon.Gear} target={<CategorySettings model={model} index={index} />} /></ActionPanel> : undefined}>
    {index && !total && <Grid.EmptyView title={query.trim() ? `No glyph answers to “${query.trim()}” yet` : "No glyphs in this view"} description="Category Settings shows every available set and Unicode block." />}
    {index && shown.map((section, i) => <Grid.Section key={i} title={section.title}>
      {section.records.map(record => <Grid.Item key={viewKey(record)} id={viewKey(record)}
        content={{ value: tileText(record, tone), tooltip: record.name }}
        actions={<GlyphActions record={record} index={index} query={query} model={model ?? undefined} />} />)}
    </Grid.Section>)}
  </Grid>;
}
