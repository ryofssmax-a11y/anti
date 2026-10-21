import path from "node:path";
import { fileURLToPath } from "node:url";
import Anthropic from "@anthropic-ai/sdk";
import express from "express";
import { CARD_BY_ID, SPREAD_BY_ID, type DrawnCard } from "../shared/cards.ts";
import { PERSONAS, type PersonaId } from "../shared/personas.ts";
import { readingRequest, systemPrompt } from "../shared/prompt.ts";

const MODEL = process.env.TAROT_MODEL ?? "claude-opus-5-5";
const PORT = Number(process.env.PORT ?? 8787);

const MAX_QUESTION = 500;
const MAX_FOLLOWUP_USER = 500;
const MAX_FOLLOWUP_ASSISTANT = 8000;
const MAX_FOLLOWUP_TURNS = 20;

// 1IPあたり10分で30回まで（APIの使いすぎ防止）
const RATE_WINDOW_MS = 10 * 60 * 1000;
const RATE_LIMIT = 30;
const hits = new Map<string, number[]>();

function rateLimited(ip: string): boolean {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < RATE_WINDOW_MS);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > RATE_LIMIT;
}

interface ReadingBody {
  question: string;
  spreadId: string;
  persona: PersonaId;
  cards: DrawnCard[];
  followups: { role: "user" | "assistant"; content: string }[];
}

function parseBody(body: unknown): ReadingBody | string {
  if (!body || typeof body !== "object") return "リクエストが不正です";
  const b = body as Record<string, unknown>;
  const question = typeof b.question === "string" ? b.question.trim() : "";
  if (question.length > MAX_QUESTION) return `質問は${MAX_QUESTION}文字以内にしてください`;

  const spreadId = typeof b.spreadId === "string" ? b.spreadId : "";
  const spread = SPREAD_BY_ID.get(spreadId);
  if (!spread) return "スプレッドが不正です";

  const persona = (typeof b.persona === "string" && b.persona in PERSONAS ? b.persona : "mystic") as PersonaId;

  if (!Array.isArray(b.cards) || b.cards.length !== spread.positions.length) return "カードの枚数が不正です";
  const cards: DrawnCard[] = [];
  const seen = new Set<string>();
  for (const c of b.cards) {
    if (!c || typeof c.cardId !== "string" || !CARD_BY_ID.has(c.cardId) || seen.has(c.cardId)) return "カードが不正です";
    seen.add(c.cardId);
    cards.push({ cardId: c.cardId, reversed: c.reversed === true });
  }

  const followupsRaw = Array.isArray(b.followups) ? b.followups : [];
  if (followupsRaw.length > MAX_FOLLOWUP_TURNS) return "会話が長すぎます。新しく占い直してください";
  const followups: ReadingBody["followups"] = [];
  for (const [i, m] of followupsRaw.entries()) {
    // 初回リーディングの後は assistant → user の順で交互に続き、最後は user の質問
    const role = i % 2 === 0 ? "assistant" : "user";
    const limit = role === "user" ? MAX_FOLLOWUP_USER : MAX_FOLLOWUP_ASSISTANT;
    if (!m || m.role !== role || typeof m.content !== "string" || !m.content.trim() || m.content.length > limit) {
      return "会話の形式が不正です";
    }
    followups.push({ role, content: m.content });
  }
  if (followups.length > 0 && followups.length % 2 !== 0) return "会話の形式が不正です";

  return { question, spreadId, persona, cards, followups };
}

const client = new Anthropic();
const app = express();
app.use(express.json({ limit: "100kb" }));

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, aiConfigured: Boolean(process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN) });
});

app.post("/api/reading", async (req, res) => {
  if (rateLimited(req.ip ?? "unknown")) {
    res.status(429).json({ error: "少し時間をおいてから、もう一度お試しください" });
    return;
  }
  const parsed = parseBody(req.body);
  if (typeof parsed === "string") {
    res.status(400).json({ error: parsed });
    return;
  }

  // 過去のAIの回答はテキストだけを送り返す（思考ブロックは保持しないので履歴の整合チェックの対象外）
  const messages: Anthropic.Beta.BetaMessageParam[] = [
    { role: "user", content: readingRequest(parsed.question, parsed.spreadId, parsed.cards) },
    ...parsed.followups,
  ];

  // 1行1イベントのJSON（NDJSON）で返す
  res.setHeader("Content-Type", "application/x-ndjson; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache");
  const send = (event: Record<string, unknown>) => res.write(JSON.stringify(event) + "\n");

  const stream = client.beta.messages.stream({
    model: MODEL,
    max_tokens: 16000,
    output_config: { effort: "low" },
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: systemPrompt(parsed.persona),
    messages,
  });
  res.on("close", () => {
    if (!res.writableEnded) stream.abort();
  });

  try {
    stream.on("text", (text) => send({ type: "text", text }));
    const message = await stream.finalMessage();
    if (message.stop_reason === "refusal") {
      send({ type: "error", message: "この内容ではリーディングできませんでした。質問の言い方を変えてお試しください。" });
    } else {
      send({ type: "done", truncated: message.stop_reason === "max_tokens" });
    }
  } catch (error) {
    if (stream.aborted) return;
    console.error(error);
    let message = "リーディング中にエラーが起きました。もう一度お試しください。";
    if (error instanceof Anthropic.AuthenticationError) message = "サーバーのAPIキーが正しく設定されていません。";
    else if (error instanceof Anthropic.RateLimitError) message = "混み合っています。少し時間をおいてお試しください。";
    send({ type: "error", message });
  }
  res.end();
});

// 本番では Vite でビルドした画面も配信する
const distDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../dist");
app.use(express.static(distDir));
app.get(/^(?!\/api\/).*/, (_req, res) => res.sendFile(path.join(distDir, "index.html")));

app.listen(PORT, () => {
  console.log(`Tarot server listening on http://localhost:${PORT}`);
});
