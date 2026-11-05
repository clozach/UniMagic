/** Untrusted data.json boundary, shared by every host: persisted types, validation, migrations. */
import {
  type LearnedAlias,
  type UnimagicData,
  type UsageEntry,
  CURRENT_DATA_VERSION,
  emptyData,
} from "./schema";

export interface UnimagicSettings {
  closeAfterInsert: boolean;
  clearSearchOnReopen: boolean;
  replayHints: boolean;
}

export const DEFAULT_SETTINGS: UnimagicSettings = {
  closeAfterInsert: true,
  clearSearchOnReopen: false,
  replayHints: true,
};

export interface Persisted {
  settings: UnimagicSettings;
  learning: UnimagicData;
}

export class UnsupportedDataVersionError extends Error {
  constructor(version: number) {
    super(
      `data.json version ${version} is newer than this Unimagic build ` +
        `(supports ${CURRENT_DATA_VERSION}); refusing to rewrite it.`,
    );
    this.name = "UnsupportedDataVersionError";
  }
}

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function validUsage(value: unknown): UsageEntry[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((row): row is UsageEntry => {
      const r = object(row);
      return !!r && typeof r.hexseq === "string" && typeof r.count === "number" &&
        Number.isFinite(r.count) && r.count >= 0;
    })
    .map((row) => ({ hexseq: row.hexseq, count: row.count }));
}

function validLearned(value: unknown): LearnedAlias[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((row): row is LearnedAlias => {
      const r = object(row);
      return !!r && typeof r.term === "string" && typeof r.hexseq === "string" &&
        (r.type === "learned" || r.type === "provisional") &&
        typeof r.score === "number" && Number.isFinite(r.score);
    })
    .map((row) => ({ ...row }));
}

/** Parse/migrate untrusted data.json without letting malformed rows poison UI. */
export function migrate(raw: unknown): { data: Persisted; invalidateIndex: boolean } {
  const root = object(raw) ?? {};
  const rawSettings = object(root.settings) ?? {};
  const rawLearning = object(root.learning);
  const fromVersion = rawLearning && typeof rawLearning.version === "number" &&
      Number.isInteger(rawLearning.version) && rawLearning.version >= 0
    ? rawLearning.version
    : 0;

  if (fromVersion > CURRENT_DATA_VERSION) {
    throw new UnsupportedDataVersionError(fromVersion);
  }

  const learning = rawLearning
    ? {
        version: fromVersion,
        usage: validUsage(rawLearning.usage),
        learned: validLearned(rawLearning.learned),
      }
    : emptyData();

  // Migration map: version → transform. v0 used the same arrays but no
  // explicit version contract, so normalization above is its migration.
  const migrations: Record<number, (d: UnimagicData) => UnimagicData> = {
    0: (d) => d,
  };
  let migrated = learning;
  let version = fromVersion;
  while (version < CURRENT_DATA_VERSION) {
    const transform = migrations[version];
    if (!transform) break;
    migrated = transform(migrated);
    version += 1;
  }
  migrated = { ...migrated, version: CURRENT_DATA_VERSION };

  const setting = <K extends keyof UnimagicSettings>(key: K): UnimagicSettings[K] =>
    typeof rawSettings[key] === "boolean"
      ? (rawSettings[key] as UnimagicSettings[K])
      : DEFAULT_SETTINGS[key];

  return {
    data: {
      settings: {
        closeAfterInsert: setting("closeAfterInsert"),
        clearSearchOnReopen: setting("clearSearchOnReopen"),
        replayHints: setting("replayHints"),
      },
      learning: migrated,
    },
    invalidateIndex: fromVersion !== 0 && fromVersion !== CURRENT_DATA_VERSION,
  };
}
