/** Full pick history is separate from aggregate usage and learned alias scores. */
import type { BrowseOrigin } from "./browse-schema";

export type HistoryHost = "native-app" | "native-keyboard" | "tinycast" | "obsidian";
export type HistoryProvenance =
  | { kind: "pick"; host: HistoryHost; action: "copy" | "insert" }
  | { kind: "snapshot-import"; importID: string; source: string; position: number }
  | { kind: "legacy-aggregate"; source: string; count: number };

export interface HistoryEvent {
  eventID: string;
  glyphID: string;
  /** Exact copied/inserted string, including VS, ZWJ and skin tones. */
  symbol: string;
  /** Unix milliseconds, null when the past occurrence time is unknown. */
  occurredAt: number | null;
  provenance: HistoryProvenance;
  origin?: BrowseOrigin;
}

export interface HistoryDocument {
  schemaVersion: 1;
  /** Newest first. Snapshot entries retain source order, never fake dates. */
  events: HistoryEvent[];
  appliedImports: string[];
}

export interface HistoryPage { events: HistoryEvent[]; nextCursor: string | null }
export interface HistoryImport {
  importID: string;
  /** Newest-first source order; event IDs must be deterministic within import. */
  events: HistoryEvent[];
}
export interface HistoryAdapter {
  readHistoryPage(request: { cursor?: string; limit: number }): Promise<HistoryPage>;
  /** Existing event ID is a no-op. Never increments usage or teaches aliases. */
  appendHistoryEvent(event: HistoryEvent): Promise<void>;
  /** Preserve existing events, add missing IDs once, never overwrite live picks. */
  importHistory(snapshot: HistoryImport): Promise<{ imported: number; alreadyApplied: boolean }>;
}

export type ScreenshotSeedCell =
  | { position: number; row: number; column: number; status: "verified" | "reconstructed"; symbol: string; glyphID: string; codepoints: number[]; provenance: string; categoryIDs: string[] }
  | { position: number; row: number; column: number; status: "unresolved"; description: string; candidates: { symbol: string; codepoints: number[]; reason: string }[]; reason: string };

export interface ScreenshotSeed {
  schemaVersion: 1;
  importID: string;
  source: string;
  sourceSHA256: string;
  order: "row-major";
  cells: ScreenshotSeedCell[];
}
