/**
 * The tone picker (⌃⌘Space on a tone-capable glyph): its six tones as a filtered set in the standard
 * grid. ↵ pastes a tone once, ⌘↵ pastes it and makes it the default, ⌘D only sets the default.
 * Escape returns to the search.
 */
import { Action, ActionPanel, Grid, Icon } from "@raycast/api";
import { tonedRecords } from "../../core/glyphs";
import { copyGlyph, pasteGlyph, type GlyphProps } from "./actions";
import { TeachForm } from "./teach-form";
import { setDefaultTone, useDefaultTone } from "./tone-state";
import { TONES, toned, toneName } from "./tones";

export function TonePicker({ record, query }: GlyphProps) {
  const current = useDefaultTone();
  // Each tone learns under its own hexseq, so a word can mean 🧘🏻‍♀️ rather than 🧘‍♀️.
  const learners = [record, ...tonedRecords(record)];
  return (
    <Grid
      columns={8}
      inset={Grid.Inset.Medium}
      filtering={false}
      navigationTitle={`${record.name} — skin tones`}
      searchBarPlaceholder={`Skin tones of ${record.name} · Esc returns to search`}
      selectedItemId={current}
    >
      <Grid.Section title={`${record.name} · default tone: ${toneName(current)}`}>
        {TONES.map((tone, i) => {
          const glyph = toned(record, tone.id);
          const learner = { ...(learners[i] ?? record), symbol: glyph };
          return (
            <Grid.Item
              key={tone.id}
              id={tone.id}
              title={tone.name}
              content={{ value: glyph, tooltip: `${record.name}: ${tone.name}` }}
              actions={
                <ActionPanel>
                  <Action
                    title={`Paste ${glyph} ${tone.name}`}
                    icon={Icon.Clipboard}
                    onAction={() => pasteGlyph(learner, glyph, query)}
                  />
                  <Action
                    title="Paste and Make Default Tone"
                    icon={Icon.CheckCircle}
                    shortcut={{ modifiers: ["cmd"], key: "return" }}
                    onAction={async () => {
                      await setDefaultTone(tone.id);
                      await pasteGlyph(learner, glyph, query);
                    }}
                  />
                  <Action
                    title={`Make ${tone.name} the Default Tone`}
                    icon={Icon.Checkmark}
                    shortcut={{ modifiers: ["cmd"], key: "d" }}
                    onAction={() => setDefaultTone(tone.id)}
                  />
                  <Action.Push
                    title={`Teach ${glyph} a Word`}
                    icon={Icon.Plus}
                    shortcut={{ modifiers: ["cmd"], key: "t" }}
                    target={<TeachForm record={learner} />}
                  />
                  <Action
                    title={`Copy ${glyph}`}
                    icon={Icon.CopyClipboard}
                    shortcut={{ modifiers: ["cmd", "shift"], key: "return" }}
                    onAction={() => copyGlyph(learner, glyph, query)}
                  />
                </ActionPanel>
              }
            />
          );
        })}
      </Grid.Section>
    </Grid>
  );
}
