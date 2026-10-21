import type { DrawnCard } from "../shared/cards.ts";
import type { PersonaId } from "../shared/personas.ts";
import type { ChatMessage } from "./storage.ts";

export interface ReadingParams {
  question: string;
  spreadId: string;
  persona: PersonaId;
  cards: DrawnCard[];
  followups: ChatMessage[];
}

/** AIリーディングをストリーミングで受け取る。onText にはそこまでの全文を渡す */
export async function streamReading(params: ReadingParams, onText: (fullText: string) => void, signal?: AbortSignal): Promise<string> {
  const res = await fetch("/api/reading", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(params),
    signal,
  });
  if (!res.ok || !res.body) {
    const body = await res.json().catch(() => null);
    throw new Error(body?.error ?? "サーバーに接続できませんでした");
  }

  const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = "";
  let text = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += value;
    let newline: number;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      if (!line) continue;
      const event = JSON.parse(line);
      if (event.type === "text") {
        text += event.text;
        onText(text);
      } else if (event.type === "error") {
        throw new Error(event.message);
      } else if (event.type === "done") {
        return text;
      }
    }
  }
  throw new Error("通信が途中で切れました。もう一度お試しください");
}
