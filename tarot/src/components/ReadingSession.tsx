import { useEffect, useRef, useState } from "react";
import { CARD_BY_ID, SPREAD_BY_ID } from "../../shared/cards.ts";
import { PERSONAS } from "../../shared/personas.ts";
import { streamReading } from "../api.ts";
import type { ChatMessage, ReadingRecord } from "../storage.ts";
import { CardView, keywordsOf } from "./CardView.tsx";
import { Markdown } from "./Markdown.tsx";

const FOLLOWUP_SUGGESTIONS = ["具体的にどう行動すればいい？", "一番大事なカードはどれ？", "注意すべきことは？"];
const MAX_FOLLOWUPS = 10;

interface ReadingSessionProps {
  record: ReadingRecord;
  /** 新しく引いたカードは伏せた状態から始める */
  startFaceDown: boolean;
  onUpdate: (record: ReadingRecord) => void;
  onNew: () => void;
}

export function ReadingSession({ record, startFaceDown, onUpdate, onNew }: ReadingSessionProps) {
  const spread = SPREAD_BY_ID.get(record.spreadId)!;
  const [revealed, setRevealed] = useState<boolean[]>(() => record.cards.map(() => !startFaceDown));
  const [selected, setSelected] = useState<number | null>(null);
  const [streaming, setStreaming] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [input, setInput] = useState("");
  const abortRef = useRef<AbortController | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const allRevealed = revealed.every(Boolean);

  const ask = async (messages: ChatMessage[]) => {
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    setError(null);
    setStreaming("");
    try {
      const answer = await streamReading(
        { question: record.question, spreadId: record.spreadId, persona: record.persona, cards: record.cards, followups: messages },
        setStreaming,
        controller.signal,
      );
      onUpdate({ ...record, messages: [...messages, { role: "assistant", content: answer }] });
    } catch (e) {
      if (controller.signal.aborted) return;
      setError(e instanceof Error ? e.message : String(e));
      // 失敗した質問は取り消して入力欄に戻す
      const last = messages.at(-1);
      if (last?.role === "user") {
        onUpdate({ ...record, messages: messages.slice(0, -1) });
        setInput(last.content);
      }
    } finally {
      if (abortRef.current === controller) {
        abortRef.current = null;
        setStreaming(null);
      }
    }
  };

  // 全カードが開いたら最初のリーディングを始める
  useEffect(() => {
    if (allRevealed && record.messages.length === 0 && streaming === null && !error) void ask([]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [allRevealed]);

  useEffect(() => () => abortRef.current?.abort(), []);

  useEffect(() => {
    if (streaming !== null) bottomRef.current?.scrollIntoView({ block: "end", behavior: "smooth" });
  }, [streaming === null, record.messages.length]);

  const sendFollowup = (text: string) => {
    const q = text.trim();
    if (!q || streaming !== null) return;
    setInput("");
    const messages: ChatMessage[] = [...record.messages, { role: "user", content: q }];
    onUpdate({ ...record, messages });
    void ask(messages);
  };

  const followupCount = record.messages.filter((m) => m.role === "user").length;
  const selectedCard = selected !== null ? record.cards[selected] : null;

  return (
    <section className="session">
      <p className="eyebrow">
        {spread.name}・{PERSONAS[record.persona].name}
      </p>
      <h2 className="title">{record.question || "全体の運勢"}</h2>

      <div className={`spread spread-${spread.id}`}>
        {record.cards.map((d, i) => (
          <div key={d.cardId} className="spread-slot" style={{ gridArea: `p${i}` }}>
            <CardView
              drawn={d}
              faceUp={revealed[i]}
              size={spread.id === "celtic" ? "sm" : "md"}
              onClick={() => (revealed[i] ? setSelected(selected === i ? null : i) : setRevealed((r) => r.map((v, j) => v || j === i)))}
              label={`${spread.positions[i]}のカードをめくる`}
            />
            <span className="slot-label">
              {spread.positions[i]}
              {revealed[i] && d.reversed && <small className="slot-rev">逆</small>}
            </span>
          </div>
        ))}
      </div>

      {!allRevealed && (
        <div className="btn-row">
          <p className="hint">カードをタップしてめくってください</p>
          <button type="button" className="btn" onClick={() => setRevealed(record.cards.map(() => true))}>
            すべてめくる
          </button>
        </div>
      )}

      {selectedCard && (
        <div className="card-detail">
          <strong>
            {spread.positions[selected!]}：{CARD_BY_ID.get(selectedCard.cardId)!.name}（{selectedCard.reversed ? "逆位置" : "正位置"}）
          </strong>
          <ul className="chips">
            {keywordsOf(selectedCard).map((k) => (
              <li key={k}>{k}</li>
            ))}
          </ul>
        </div>
      )}

      {allRevealed && (
        <div className="chat">
          {record.messages.map((m, i) =>
            m.role === "assistant" ? (
              <article key={i} className="bubble bubble-ai">
                <Markdown text={m.content} />
              </article>
            ) : (
              <p key={i} className="bubble bubble-user">
                {m.content}
              </p>
            ),
          )}
          {streaming !== null && (
            <article className="bubble bubble-ai is-streaming">
              {streaming ? <Markdown text={streaming} /> : <p className="loading">カードの声に耳を澄ませています…</p>}
            </article>
          )}
          {error && (
            <div className="error" role="alert">
              <p>{error}</p>
              {record.messages.length === 0 && (
                <button type="button" className="btn" onClick={() => void ask([])}>
                  もう一度リーディングする
                </button>
              )}
            </div>
          )}

          {record.messages.length > 0 && streaming === null && (
            followupCount < MAX_FOLLOWUPS ? (
              <form
                className="followup"
                onSubmit={(e) => {
                  e.preventDefault();
                  sendFollowup(input);
                }}
              >
                <div className="examples">
                  {FOLLOWUP_SUGGESTIONS.map((q) => (
                    <button type="button" key={q} className="chip-btn" onClick={() => sendFollowup(q)}>
                      {q}
                    </button>
                  ))}
                </div>
                <div className="followup-row">
                  <input value={input} onChange={(e) => setInput(e.target.value)} maxLength={500} placeholder="このリーディングについて質問する" />
                  <button type="submit" className="btn btn-primary" disabled={!input.trim()}>
                    送信
                  </button>
                </div>
              </form>
            ) : (
              <p className="hint">このリーディングで質問できる回数の上限に達しました。新しく占ってみましょう。</p>
            )
          )}
          <div ref={bottomRef} />
        </div>
      )}

      <button type="button" className="btn btn-block" onClick={onNew}>
        新しく占う
      </button>
    </section>
  );
}
