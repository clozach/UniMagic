/** esbuild `base64` loader: importing a `.gz` yields its contents base64-encoded.
 * Used to inline the corpus into the bundle (the only file that reaches iOS). */
declare module "*.gz" {
  const base64: string;
  export default base64;
}

/** Tinycast host: the corpus JSON inlined as text by esbuild.tinycast.mjs. */
declare module "unimagic-corpus-text" {
  const text: string;
  export default text;
}
