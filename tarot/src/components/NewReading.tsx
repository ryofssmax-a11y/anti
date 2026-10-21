import { useState } from "react";
import { SPREADS, type DrawnCard } from "../../shared/cards.ts";
import { PERSONAS, type PersonaId } from "../../shared/personas.ts";
import { shuffledDeck } from "../random.ts";
import { CardView } from "./CardView.tsx";

const PICK_POOL = 22;
const QUESTION_EXAMPLES = ["気になる人との関係はどうなる？", "今の仕事を続けるべき？", "今月の運勢を教えて", "最近モヤモヤする理由は？"];

interface NewReadingProps {
  persona: PersonaId;
  allowReversed: boolean;
  onPersonaChange: (persona: PersonaId) => void;
  onComplete: (params: { question: string; spreadId: string; persona: PersonaId; cards: DrawnCard[] }) => void;
}

export function NewReading({ persona, allowReversed, onPersonaChange, onComplete }: NewReadingProps) {
  const [stage, setStage] = useState<"setup" | "shuffle" | "pick">("setup");
  const [question, setQuestion] = useState("");
  const [spreadId, setSpreadId] = useState("three");
  const [deck, setDeck] = useState<DrawnCard[]>([]);
  const [shuffling, setShuffling] = useState(false);
  const [shuffleCount, setShuffleCount] = useState(0);
  const [picked, setPicked] = useState<number[]>([]);

  const spread = SPREADS.find((s) => s.id === spreadId)!;

  const shuffle = () => {
    if (shuffling) return;
    setShuffling(true);
    setDeck(shuffledDeck(allowReversed));
    setTimeout(() => {
      setShuffling(false);
      setShuffleCount((n) => n + 1);
    }, 1100);
  };

  const togglePick = (i: number) => {
    setPicked((p) => (p.includes(i) ? p.filter((x) => x !== i) : p.length < spread.positions.length ? [...p, i] : p));
  };

  if (stage === "setup") {
    return (
      <section className="setup">
        <h2 className="title">何を占いますか？</h2>
        <label className="field">
          <span className="field-label">質問（空欄なら全体運を占います）</span>
          <textarea value={question} onChange={(e) => setQuestion(e.target.value)} maxLength={500} rows={3} placeholder="例：気になる人との関係はどうなる？" />
        </label>
        <div className="examples">
          {QUESTION_EXAMPLES.map((q) => (
            <button type="button" key={q} className="chip-btn" onClick={() => setQuestion(q)}>
              {q}
            </button>
          ))}
        </div>

        <span className="field-label">スプレッド</span>
        <div className="option-grid">
          {SPREADS.map((s) => (
            <button type="button" key={s.id} className={`option ${s.id === spreadId ? "is-selected" : ""}`} onClick={() => setSpreadId(s.id)}>
              <strong>{s.name}</strong>
              <span>
                {s.positions.length}枚・{s.description}
              </span>
            </button>
          ))}
        </div>

        <span className="field-label">占い師</span>
        <div className="option-grid">
          {(Object.keys(PERSONAS) as PersonaId[]).map((id) => (
            <button type="button" key={id} className={`option ${id === persona ? "is-selected" : ""}`} onClick={() => onPersonaChange(id)}>
              <strong>{PERSONAS[id].name}</strong>
              <span>{PERSONAS[id].description}</span>
            </button>
          ))}
        </div>

        <button
          type="button"
          className="btn btn-primary btn-block"
          onClick={() => {
            setStage("shuffle");
            shuffle();
          }}
        >
          カードをシャッフルする
        </button>
      </section>
    );
  }

  if (stage === "shuffle") {
    return (
      <section className="shuffle">
        <h2 className="title">心の中で質問を唱えてください</h2>
        {question && <p className="question-quote">「{question}」</p>}
        <div className={`deck-stack ${shuffling ? "is-shuffling" : ""}`} aria-hidden="true">
          {Array.from({ length: 7 }, (_, i) => (
            <div key={i} className="card card-md stack-card" style={{ ["--i" as string]: i }}>
              <div className="card-inner">
                <div className="card-back" />
              </div>
            </div>
          ))}
        </div>
        <p className="hint">{shuffling ? "シャッフル中…" : `${shuffleCount}回シャッフルしました。納得できたら次へ進みましょう`}</p>
        <div className="btn-row">
          <button type="button" className="btn" onClick={shuffle} disabled={shuffling}>
            もう一度シャッフル
          </button>
          <button type="button" className="btn btn-primary" onClick={() => setStage("pick")} disabled={shuffling}>
            カードを選ぶ
          </button>
        </div>
      </section>
    );
  }

  const done = picked.length === spread.positions.length;
  return (
    <section className="pick">
      <h2 className="title">直感で {spread.positions.length} 枚選んでください</h2>
      <p className="hint">
        {done ? "選び終わりました" : `次は「${spread.positions[picked.length]}」のカード（${picked.length}/${spread.positions.length}）`}
      </p>
      <div className="fan">
        {deck.slice(0, PICK_POOL).map((d, i) => {
          const order = picked.indexOf(i);
          return (
            <div key={d.cardId} className={`fan-slot ${order >= 0 ? "is-picked" : ""}`} style={{ ["--i" as string]: i, ["--n" as string]: PICK_POOL }}>
              <CardView drawn={d} faceUp={false} size="sm" onClick={() => togglePick(i)} label={`${i + 1}番目のカード`} />
              {order >= 0 && <span className="pick-order">{order + 1}</span>}
            </div>
          );
        })}
      </div>
      <div className="btn-row">
        <button type="button" className="btn" onClick={() => setPicked([])} disabled={!picked.length}>
          選び直す
        </button>
        <button
          type="button"
          className="btn btn-primary"
          disabled={!done}
          onClick={() => onComplete({ question: question.trim(), spreadId, persona, cards: picked.map((i) => deck[i]) })}
        >
          カードを開く
        </button>
      </div>
    </section>
  );
}
