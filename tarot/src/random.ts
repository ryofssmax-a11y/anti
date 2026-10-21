import { CARDS, type DrawnCard } from "../shared/cards.ts";

function randomInt(max: number): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return buf[0] % max;
}

/** Fisher–Yates でシャッフルした78枚を返す */
export function shuffledDeck(allowReversed: boolean): DrawnCard[] {
  const deck = CARDS.map((c) => ({ cardId: c.id, reversed: allowReversed && randomInt(2) === 1 }));
  for (let i = deck.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

export function drawOne(allowReversed: boolean): DrawnCard {
  return shuffledDeck(allowReversed)[0];
}
