import { dirname, join } from "node:path";
import { useEffect, useReducer } from "react";
import { Toast, showToast } from "@raycast/api";
import { DesktopBrowse, type DesktopRecord } from "../shared/desktop-browse";
import { personalizationFileProvider } from "../shared/personalization-file";
import type { IndexBundle } from "../../core/search";

let runtime: DesktopBrowse | null = null;
let currentFile = "";
export function openPersonalization(index: IndexBundle, learnedWordsFile: string): DesktopBrowse {
  if (!runtime || runtime.index !== index || currentFile !== learnedWordsFile) {
    runtime = new DesktopBrowse(index, personalizationFileProvider(join(dirname(learnedWordsFile), "personalization-v1.json"), "shared-read-write"));
    currentFile = learnedWordsFile;
  }
  return runtime;
}
export function usePersonalization(model?: DesktopBrowse | null): void {
  const [, update] = useReducer(n => n + 1, 0);
  useEffect(() => model?.subscribe(update), [model]);
}
export async function recordHistory(record: DesktopRecord, symbol: string, action: "copy" | "insert"): Promise<void> {
  if (!runtime) return;
  try { await runtime.picked(record, symbol, "tinycast", action); }
  catch (error) { await showToast({ style: Toast.Style.Failure, title: "Glyph used; history could not be saved", message: String(error) }); }
}
