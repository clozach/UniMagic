/**
 * The union corpus, inlined into the command bundle as JSON text. Tinycast passes file
 * bytes to JavaScript as base64, so reading 17 MB through `fs` costs far more than
 * letting JavaScriptCore parse a string literal it already holds.
 */
import CORPUS_TEXT from "unimagic-corpus-text";
import { buildIndex, type Corpus, type IndexBundle } from "../../core";
import { desktopCorpus } from "../shared/desktop-browse";

export function loadIndex(): IndexBundle {
  return buildIndex(desktopCorpus(JSON.parse(CORPUS_TEXT) as Corpus));
}
