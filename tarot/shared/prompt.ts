import { CARD_BY_ID, SPREAD_BY_ID, type DrawnCard } from "./cards.ts";
import { PERSONAS, type PersonaId } from "./personas.ts";

// AIへの指示。サーバー（Claude API）とアーティファクト版（claude.ai の sample）の両方で使う。

export const BASE_SYSTEM = `あなたはタロット占いアプリの占い師です。ユーザーの質問と、引かれたカード（スプレッド上の位置・正位置/逆位置）をもとにリーディングを行います。

リーディングの方針:
- 各カードの意味を、その位置の役割とユーザーの質問に結びつけて解釈する。カード同士のつながり（流れ・対比・スートや大アルカナの偏り）にも触れる。
- 最後に、今日からできる具体的なアドバイスを1〜3個示す。
- 未来を断定せず、「〜の兆し」「〜しやすい」のように可能性として伝える。不安をあおらない。
- 健康・お金・法律などの深刻な判断が必要な相談では、専門家への相談も自然に勧める。
- 自傷や命に関わる深刻な悩みがうかがえるときは、占いより先に気持ちを受け止め、信頼できる人や相談窓口（日本ならいのちの電話など）につながるよう優しく促す。
- 日本語で答える。見出しや箇条書きなどのMarkdownを使って読みやすくする。初回のリーディングは全体で600〜1200字程度、追加の質問への回答は短めにする。
- タロットの範囲を大きく外れる依頼には、占い師として自然な範囲で応じる。`;

export function systemPrompt(persona: PersonaId): string {
  return `${BASE_SYSTEM}\n\n話し方: ${PERSONAS[persona].style}`;
}

export function readingRequest(question: string, spreadId: string, cards: DrawnCard[]): string {
  const spread = SPREAD_BY_ID.get(spreadId)!;
  const lines = cards.map((drawn, i) => {
    const card = CARD_BY_ID.get(drawn.cardId)!;
    const keywords = drawn.reversed ? card.reversed : card.upright;
    return `${i + 1}. 【${spread.positions[i]}】${card.name}（${card.nameEn}）${drawn.reversed ? "逆位置" : "正位置"} — キーワード: ${keywords.join("、")}`;
  });
  return `質問: ${question || "（特に質問はなし。全体的な運勢を見てほしい）"}
スプレッド: ${spread.name}

引いたカード:
${lines.join("\n")}

このカードでリーディングしてください。`;
}
