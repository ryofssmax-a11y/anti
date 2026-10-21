import type { DrawnCard } from "../shared/cards.ts";
import type { PersonaId } from "../shared/personas.ts";
import { readingRequest, systemPrompt } from "../shared/prompt.ts";
import type { ChatMessage } from "./storage.ts";

// claude.ai のアーティファクトとして開いたときは、閲覧者の Claude（sample 機能）でリーディングする。
// それ以外では自前のサーバー（/api/reading）を使う。
interface SampleError {
  code: string;
  message: string;
}
type Sample = (
  input: ChatMessage[],
  options: { onText?: (u: { text: string }) => void; signal?: AbortSignal; cache?: boolean; effort?: "low" | "medium" | "high" },
) => Promise<{ text: string; truncated: boolean }>;

declare global {
  interface Window {
    claude?: { use(name: string): Promise<unknown> };
  }
}

let samplePromise: Promise<Sample | null> | null = null;
function getSample(): Promise<Sample | null> {
  samplePromise ??= window.claude ? (window.claude.use("sample") as Promise<Sample | null>).catch(() => null) : Promise.resolve(null);
  return samplePromise;
}

/** AIリーディングが使えるか（アーティファクトの sample か、APIキーの設定されたサーバー） */
export async function aiAvailable(): Promise<boolean> {
  if (await getSample()) return true;
  try {
    const health = await (await fetch("/api/health")).json();
    return Boolean(health.aiConfigured);
  } catch {
    return false;
  }
}

const SAMPLE_ERRORS: Record<string, string> = {
  not_granted: "Claudeの利用が許可されていません。許可するとAIリーディングが使えます。",
  sampling_disabled: "このアカウントではClaudeを使えません。",
  rate_limited: "混み合っています。少し時間をおいてお試しください。",
  refused: "この内容ではリーディングできませんでした。質問の言い方を変えてお試しください。",
  session_expired: "ログインし直してからお試しください。",
};

async function sampleReading(sample: Sample, params: ReadingParams, onText: (fullText: string) => void, signal?: AbortSignal) {
  const instructions = `${systemPrompt(params.persona)}\n\n---\n\n${readingRequest(params.question, params.spreadId, params.cards)}`;
  try {
    const { text } = await sample([{ role: "user", content: instructions }, ...params.followups], {
      onText: ({ text }) => onText(text),
      signal,
      cache: false,
      effort: "low",
    });
    return text;
  } catch (e) {
    const err = e as SampleError;
    if (err.code === "cancelled") throw new Error("cancelled");
    throw new Error(SAMPLE_ERRORS[err.code] ?? "リーディング中にエラーが起きました。もう一度お試しください。");
  }
}

export interface ReadingParams {
  question: string;
  spreadId: string;
  persona: PersonaId;
  cards: DrawnCard[];
  followups: ChatMessage[];
}

/** AIリーディングをストリーミングで受け取る。onText にはそこまでの全文を渡す */
export async function streamReading(params: ReadingParams, onText: (fullText: string) => void, signal?: AbortSignal): Promise<string> {
  const sample = await getSample();
  if (sample) return sampleReading(sample, params, onText, signal);

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
