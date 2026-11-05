/** "Teach it a word": a provisional alias that graduates to learned on the next pick. */
import { Action, ActionPanel, Form, Toast, showToast, useNavigation } from "@raycast/api";
import type { CorpusRecord } from "../../core";
import { teachWord } from "./learning";

export function TeachForm({ record }: { record: CorpusRecord }) {
  const { pop } = useNavigation();
  const submit = async ({ term }: { term: string }) => {
    const word = term.trim();
    if (!word) return;
    teachWord(record, word);
    await showToast({ style: Toast.Style.Success, title: `${record.symbol} now answers to “${word}”` });
    pop();
  };
  return (
    <Form
      navigationTitle={`Teach ${record.symbol}`}
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Teach Word" onSubmit={submit} />
        </ActionPanel>
      }
    >
      <Form.Description text={`${record.symbol}   ${record.name}`} />
      <Form.TextField id="term" title="Word" placeholder="a word you'll search for" autoFocus />
      <Form.Description text="Searching this word finds the glyph at once; picking it from that search makes the word stick." />
    </Form>
  );
}
