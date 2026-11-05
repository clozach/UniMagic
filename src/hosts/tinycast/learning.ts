/**
 * One learning store per command run, shared by the grid and every pushed screen.
 * Raycast renders a pushed view outside the pusher's React tree, so context cannot
 * carry it; a module-level store read through useSyncExternalStore can.
 */
import { useSyncExternalStore } from "react";
import {
  emptyData,
  recordUsage,
  teach,
  unlearn,
  upVote,
  type CorpusRecord,
  type UnimagicData,
} from "../../core";
import { mutateShared, readShared, type SharedData } from "./shared-store";

let file = "";
let state: SharedData = { kind: "ready", data: emptyData() };
const listeners = new Set<() => void>();

export function openLearning(dataFile: string): SharedData {
  file = dataFile;
  state = readShared(file);
  return state;
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useLearning(): SharedData {
  return useSyncExternalStore(subscribe, () => state);
}

/** What the picker ranks with: the shared words when readable, nothing learned otherwise. */
export function learnedData(shared: SharedData): UnimagicData {
  return shared.kind === "ready" ? shared.data : emptyData();
}

function mutate(change: (data: UnimagicData) => UnimagicData): void {
  if (state.kind !== "ready") return;
  state = mutateShared(file, change);
  for (const listener of [...listeners]) listener();
}

/** A pick teaches the query's words and counts toward Frequently used, as in Obsidian. */
export function rememberPick(record: CorpusRecord, query: string): void {
  mutate((data) => {
    const counted = recordUsage(data, record.hexseq);
    return query.trim() ? upVote(counted, query, record.hexseq) : counted;
  });
}

export function teachWord(record: CorpusRecord, term: string): void {
  mutate((data) => teach(data, term, record.hexseq));
}

export function forgetWord(record: CorpusRecord, term: string): void {
  mutate((data) => unlearn(data, term, record.hexseq));
}
