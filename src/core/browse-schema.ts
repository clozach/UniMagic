/** Wire contract shared by generated catalogue, native and desktop hosts. */
export type CategoryID = string;
export type GlyphID = string;

export type CategoryExemplar =
  | { kind: "unicode"; symbol: string }
  | { kind: "emoji"; symbol: string }
  | { kind: "custom-font"; symbol: string; font: "UniCharCategories" };

export type CategorySource =
  | { kind: "curated-set"; set: string }
  | { kind: "legacy-ranges"; ranges: [number, number][] }
  | { kind: "unichar-observed"; referenceID: string }
  | { kind: "unicode-block"; block: string; startScalar: number }
  | { kind: "utility"; utility: "recents" | "frequent" };

/** Occurrence identity survives duplicate symbols and presentation selectors. */
export interface BrowseOccurrence {
  occurrenceID: string;
  glyphID: GlyphID;
  symbol: string;
  name?: string;
}

export interface BrowseCategoryDefinition {
  id: CategoryID;
  title: string;
  source: CategorySource;
  defaultEnabled: boolean;
  defaultExemplar: CategoryExemplar;
  /** Immutable numeric scalar sequence; unrelated to search order/exemplars. */
  orderKey: number[];
  /** Original observed/curated order; never inferred by sorting display text. */
  sample: BrowseOccurrence[];
  /** Rules reference the unchanged corpus; explicit inventory retains duplicates. */
  membership:
    | { kind: "source-rule" }
    | { kind: "explicit"; entries: BrowseOccurrence[] };
  memberCount: number;
  unresolvedSourceSymbols?: string[];
}

export interface BrowseCatalogue {
  schemaVersion: 2;
  revision: string;
  corpusBuild: string;
  sourceSHA256: string;
  font: { file: string; sha256: string };
  categories: BrowseCategoryDefinition[];
  /** Supplements never replace or mutate canonical corpus records. */
  supplements: { glyphID: string; symbol: string; name: string }[];
  counts: { canonical: number; supplements: number; collections: number; blocks: number; observedSampleOccurrences: number };
}

/** Missing keys inherit defaults; explicit false survives seed/revision changes. */
export interface BrowsePreferences {
  schemaVersion: 1;
  catalogueRevision: string;
  categoryVisibility: Record<CategoryID, boolean>;
  exemplarOverrides: Record<CategoryID, CategoryExemplar>;
  appliedMigrations: string[];
}

export interface BrowseOrigin {
  categoryID: CategoryID;
  occurrenceID: string;
}

export interface BrowsePreferenceAdapter {
  readPreferences(): Promise<BrowsePreferences>;
  setCategoryEnabled(categoryID: CategoryID, enabled: boolean): Promise<BrowsePreferences>;
  setCategoryExemplar(categoryID: CategoryID, exemplar: CategoryExemplar | null): Promise<BrowsePreferences>;
  /** Idempotent: explicit visibility wins; only previously absent IDs are seeded. */
  applyCategoryDefaults(migrationID: string, categoryIDs: CategoryID[]): Promise<BrowsePreferences>;
}
