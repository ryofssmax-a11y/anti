import { CARD_BY_ID, type DrawnCard, type Suit } from "../../shared/cards.ts";

const ROMAN = ["0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI"];
const RANK_LABEL = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "P", "Kn", "Q", "K"];

function SuitIcon({ suit }: { suit: Exclude<Suit, "major"> }) {
  switch (suit) {
    case "wands":
      return (
        <svg viewBox="0 0 48 48" aria-hidden="true">
          <path d="M14 40 L34 8" strokeWidth="4" strokeLinecap="round" />
          <path d="M30 12 q6 -2 6 4 M24 22 q-6 -2 -6 4 M27 17 q6 0 5 5" strokeWidth="2.5" fill="none" strokeLinecap="round" />
        </svg>
      );
    case "cups":
      return (
        <svg viewBox="0 0 48 48" aria-hidden="true">
          <path d="M12 8 h24 q0 16 -12 18 q-12 -2 -12 -18 z" strokeWidth="2.5" />
          <path d="M24 26 v10 M16 40 h16" strokeWidth="3" strokeLinecap="round" />
        </svg>
      );
    case "swords":
      return (
        <svg viewBox="0 0 48 48" aria-hidden="true">
          <path d="M24 4 L28 12 L26 32 h-4 L20 12 z" strokeWidth="2" />
          <path d="M14 32 h20 M24 32 v10" strokeWidth="3.5" strokeLinecap="round" />
        </svg>
      );
    case "pentacles":
      return (
        <svg viewBox="0 0 48 48" aria-hidden="true">
          <circle cx="24" cy="24" r="18" strokeWidth="2.5" fill="none" />
          <path d="M24 9 L32.8 36 L9.7 19.3 H38.3 L15.2 36 Z" strokeWidth="1.8" fill="none" strokeLinejoin="round" />
        </svg>
      );
  }
}

function MajorIcon({ number }: { number: number }) {
  // 大アルカナは星と月のモチーフで統一し、番号ごとに光の数を変える
  const rays = 5 + (number % 4);
  const points = Array.from({ length: rays * 2 }, (_, i) => {
    const r = i % 2 === 0 ? 18 : 7;
    const a = (Math.PI * i) / rays - Math.PI / 2;
    return `${24 + r * Math.cos(a)},${24 + r * Math.sin(a)}`;
  }).join(" ");
  return (
    <svg viewBox="0 0 48 48" aria-hidden="true">
      <polygon points={points} strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  );
}

interface CardViewProps {
  drawn: DrawnCard;
  faceUp: boolean;
  size?: "sm" | "md" | "lg";
  onClick?: () => void;
  label?: string;
}

export function CardView({ drawn, faceUp, size = "md", onClick, label }: CardViewProps) {
  const card = CARD_BY_ID.get(drawn.cardId)!;
  const Tag = onClick ? "button" : "div";
  return (
    <Tag
      type={onClick ? "button" : undefined}
      className={`card card-${size} ${faceUp ? "is-up" : ""}`}
      onClick={onClick}
      aria-label={faceUp ? `${card.name} ${drawn.reversed ? "逆位置" : "正位置"}` : (label ?? "伏せられたカード")}
    >
      <div className="card-inner">
        <div className="card-back" />
        <div className={`card-face suit-${card.suit}`}>
          <div className={`card-art ${drawn.reversed ? "is-reversed" : ""}`}>
            <span className="card-num">{card.suit === "major" ? ROMAN[card.number] : RANK_LABEL[card.number - 1]}</span>
            <div className="card-icon">{card.suit === "major" ? <MajorIcon number={card.number} /> : <SuitIcon suit={card.suit} />}</div>
            <span className="card-en">{card.nameEn}</span>
          </div>
          <span className="card-name">{card.name}</span>
          {drawn.reversed && <span className="card-rev">逆位置</span>}
        </div>
      </div>
    </Tag>
  );
}

/** 正逆位置に応じたキーワード */
export function keywordsOf(drawn: DrawnCard): string[] {
  const card = CARD_BY_ID.get(drawn.cardId)!;
  return drawn.reversed ? card.reversed : card.upright;
}
