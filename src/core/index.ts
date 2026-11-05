/**
 * Unimagic core — public barrel. Isomorphic, stateless: no Node built-ins, no
 * DOM. The host (Obsidian plugin / PWA) owns the learned-alias + usage store
 * and all persistence; core is pure schema + search + learning + compose math.
 */
export * from "./schema";
export * from "./search";
export * from "./learning";
export * from "./compose";
