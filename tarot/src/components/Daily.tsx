import { useState } from "react";
import { CARD_BY_ID, type DrawnCard } from "../../shared/cards.ts";
import { drawOne } from "../random.ts";
import { type DailyRecord, streak, todayString } from "../storage.ts";
import { CardView, keywordsOf } from "./CardView.tsx";

interface DailyProps {
  records: DailyRecord[];
  allowReversed: boolean;
  onDraw: (record: DailyRecord) => void;
  onAskAi: (card: DrawnCard) => void;
}

export function Daily({ records, allowReversed, onDraw, onAskAi }: DailyProps) {
  const today = todayString();
  const todays = records.find((r) => r.date === today);
  const [flipping, setFlipping] = useState(false);
  const days = streak(records);

  const draw = () => {
    if (todays || flipping) return;
    setFlipping(true);
    const drawn = drawOne(allowReversed);
    // めくる演出の後に記録する
    setTimeout(() => {
      onDraw({ date: today, ...drawn });
      setFlipping(false);
    }, 450);
  };

  const card = todays && CARD_BY_ID.get(todays.cardId)!;
  const [, month, day] = today.split("-").map(Number);

  return (
    <section className="daily">
      <p className="eyebrow">
        {month}月{day}日のカード
      </p>
      <h2 className="title">{todays ? "今日のあなたへのメッセージ" : "今日の1枚を引きましょう"}</h2>

      <div className="daily-stage">
        {todays ? (
          <CardView drawn={todays} faceUp size="lg" />
        ) : (
          <button type="button" className={`card card-lg daily-deck ${flipping ? "is-drawing" : ""}`} onClick={draw} aria-label="カードを引く">
            <div className="card-inner">
              <div className="card-back" />
            </div>
          </button>
        )}
      </div>

      {todays && card ? (
        <div className="daily-result">
          <h3 className="card-title">
            {card.name}
            <span className="pos-badge">{todays.reversed ? "逆位置" : "正位置"}</span>
          </h3>
          <ul className="chips">
            {keywordsOf(todays).map((k) => (
              <li key={k}>{k}</li>
            ))}
          </ul>
          <p className="daily-message">{todays.reversed ? card.messageReversed : card.message}</p>
          <button type="button" className="btn btn-primary" onClick={() => onAskAi(todays)}>
            ✦ このカードをAIで深く読む
          </button>
          <p className="hint">明日また新しいカードが引けます</p>
        </div>
      ) : (
        <div className="daily-result">
          <p className="hint">深呼吸をして、今日の自分を思い浮かべながらタップしてください</p>
          <button type="button" className="btn btn-primary" onClick={draw} disabled={flipping}>
            カードを引く
          </button>
        </div>
      )}

      <div className="streak">
        <span className="streak-num">{days}</span>
        <span>日連続</span>
        <span className="streak-sub">これまで {records.length} 回引きました</span>
      </div>
    </section>
  );
}
