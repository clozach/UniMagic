import esbuild from "esbuild";
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

// Tinycast runs Raycast's own built layout: package.json, one <command>.js, assets/.
const out = "build-tinycast";
const host = "src/hosts/tinycast";

const corpusText = {
  name: "unimagic-corpus-text",
  setup(build) {
    build.onResolve({ filter: /^unimagic-corpus-text$/ }, () => ({
      path: new URL("./unimagic-corpus.json", import.meta.url).pathname,
      namespace: "corpus-text",
    }));
    build.onLoad({ filter: /.*/, namespace: "corpus-text" }, (args) => ({
      contents: readFileSync(args.path, "utf8"),
      loader: "text",
    }));
  },
};

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
await esbuild.build({
  entryPoints: { unimagic: `${host}/unimagic.tsx` },
  bundle: true,
  platform: "node",
  format: "cjs",
  target: "es2022",
  jsx: "automatic",
  external: ["react", "react/jsx-runtime", "@raycast/api"],
  plugins: [corpusText],
  outdir: out,
  logLevel: "info",
  minify: true,
});
cpSync(`${host}/package.json`, `${out}/package.json`);
cpSync(`${host}/assets`, `${out}/assets`, { recursive: true });
mkdirSync(`${out}/assets/categories`, { recursive: true });
execFileSync("swift", [`${host}/category-icons.swift`, "ios/Resources/BrowseInventory.json", "ios/Resources/CategoryArtwork.json", `${out}/assets/categories`], { stdio: "inherit" });

// No tofu: the coverage helper and the glyph list it reads (see coverage.ts).
const corpus = JSON.parse(readFileSync("unimagic-corpus.json", "utf8"));
const rows = corpus.records.map((r) => `${r.hexseq}\t${r.symbol}`);
const catalogue = JSON.parse(readFileSync("ios/Resources/BrowseInventory.json", "utf8"));
rows.push(...catalogue.supplements.map(s => `${s.glyphID}\t${s.symbol}`));
writeFileSync(`${out}/assets/glyphs.tsv`, [`#build\t${corpus.build} / browse:${catalogue.revision}`, ...rows].join("\n"));
execFileSync("swiftc", ["-O", "-o", `${out}/assets/unimagic-coverage`, `${host}/coverage.swift`], {
  stdio: "inherit",
});
