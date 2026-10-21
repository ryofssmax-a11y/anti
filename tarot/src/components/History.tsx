import { CARD_BY_ID, CARDS, SPREAD_BY_ID, type Suit } from "../../shared/cards.ts";
import type { DailyRecord, ReadingRecord } from "../storage.ts";
import { CardView } from "./CardView.tsx";

const SUIT_LABEL: Record<Suit, string> = { major: "大アルカナ", wands: "ワンド", cups: "カップ", swords: "ソード", pentacles: "ペンタクル" };

interface HistoryProps {
  daily: DailyRecord[];
  readings: ReadingRecord[];
  onOpen: (record: ReadingRecord) => void;
  onDelete: (id: string) => void;
}

function formatDate(iso: string) {
  const d = new Date(iso);
  return `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

export function History({ daily, readings, onOpen, onDelete }: HistoryProps) {
  const allDraws = [...daily, ...readings.filter((r) => !r.fromDaily).flatMap((r) => r.cards)];
  const counts = new Map<string, number>();
  const suitCounts = new Map<Suit, number>();
  for (const d of allDraws) {
    counts.set(d.cardId, (counts.get(d.cardId) ?? 0) + 1);
    const suit = CARD_BY_ID.get(d.cardId)!.suit;
    suitCounts.set(suit, (suitCounts.get(suit) ?? 0) + 1);
  }
  const top = [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3);
  const reversedRate = allDraws.length ? Math.round((allDraws.filter((d) => d.reversed).length / allDraws.length) * 100) : 0;
  const recentDaily = [...daily].sort((a, b) => b.date.localeCompare(a.date)).slice(0, 14);

  return (
    <section className="history">
      <h2 className="title">記録</h2>

      {allDraws.length === 0 ? (
        <p className="hint">まだ記録がありません。今日の1枚を引いてみましょう。</p>
      ) : (
        <div className="stats">
          <div className="stat">
            <span className="stat-num">{allDraws.length}</span>
            <span className="stat-label">引いたカード</span>
          </div>
          <div className="stat">
            <span className="stat-num">{new Set(counts.keys()).size}<small>/{CARDS.length}</small></span>
            <span className="stat-label">出会ったカード</span>
          </div>
          <div className="stat">
            <span className="stat-num">{reversedRate}<small>%</small></span>
            <span className="stat-label">逆位置の割合</span>
          </div>
          <div className="stat stat-wide">
            <span className="stat-label">よく出るカード</span>
            <ol className="top-cards">
              {top.map(([id, n]) => (
                <li key={id}>
                  {CARD_BY_ID.get(id)!.name} <small>×{n}</small>
                </li>
              ))}
            </ol>
          </div>
          <div className="stat stat-wide">
            <span className="stat-label">スートの割合</span>
            <div className="suit-bars">
              {(Object.keys(SUIT_LABEL) as Suit[]).map((s) => {
                const pct = Math.round(((suitCounts.get(s) ?? 0) / allDraws.length) * 100);
                return (
                  <div key={s} className="suit-bar">
                    <span>{SUIT_LABEL[s]}</span>
                    <div className="bar">
                      <div className={`bar-fill suit-${s}`} style={{ width: `${pct}%` }} />
                    </div>
                    <span className="bar-pct">{pct}%</span>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {recentDaily.length > 0 && (
        <>
          <h3 className="section-title">今日の1枚（最近14回）</h3>
          <div className="daily-strip">
            {recentDaily.map((d) => (
              <div key={d.date} className="daily-strip-item">
                <CardView drawn={d} faceUp size="sm" />
                <span>{d.date.slice(5).replace("-", "/")}</span>
              </div>
            ))}
          </div>
        </>
      )}

      {readings.length > 0 && (
        <>
          <h3 className="section-title">リーディング</h3>
          <ul className="reading-list">
            {readings.map((r) => (
              <li key={r.id} className="reading-item">
                <button type="button" className="reading-open" onClick={() => onOpen(r)}>
                  <span className="reading-meta">
                    {formatDate(r.createdAt)}・{SPREAD_BY_ID.get(r.spreadId)?.name}
                  </span>
                  <strong>{r.question || "全体の運勢"}</strong>
                  <span className="reading-cards">{r.cards.map((c) => CARD_BY_ID.get(c.cardId)!.name + (c.reversed ? "(逆)" : "")).join("、")}</span>
                </button>
                <button
                  type="button"
                  className="icon-btn"
                  aria-label="削除"
                  onClick={() => {
                    if (confirm("このリーディングを削除しますか？")) onDelete(r.id);
                  }}
                >
                  ×
                </button>
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  );
}
