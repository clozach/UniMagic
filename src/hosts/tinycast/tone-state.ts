/**
 * The default skin tone, kept in the extension's own storage on this Mac. Like learning.ts it is a
 * module store, because a pushed view renders outside the pusher's React tree.
 */
import { LocalStorage } from "@raycast/api";
import { useSyncExternalStore } from "react";
import { parseTone, type ToneId } from "./tones";

const KEY = "defaultTone";
let tone: ToneId = "none";
const listeners = new Set<() => void>();

function emit(): void {
  for (const listener of [...listeners]) listener();
}

export async function loadDefaultTone(): Promise<void> {
  tone = parseTone(await LocalStorage.getItem(KEY));
  emit();
}

export async function setDefaultTone(next: ToneId): Promise<void> {
  tone = next;
  emit();
  await LocalStorage.setItem(KEY, next);
}

export function useDefaultTone(): ToneId {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    () => tone,
  );
}
