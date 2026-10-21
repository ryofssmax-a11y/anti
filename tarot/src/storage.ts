import type { DrawnCard } from "../shared/cards.ts";
import type { PersonaId } from "../shared/personas.ts";

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface DailyRecord extends DrawnCard {
  date: string; // YYYY-MM-DD（端末のローカル日付）
}

export interface ReadingRecord {
  id: string;
  createdAt: string;
  question: string;
  spreadId: string;
  persona: PersonaId;
  cards: DrawnCard[];
  /** messages[0] が最初のリーディング。以降は user と assistant が交互に続く */
  messages: ChatMessage[];
  /** 今日の1枚から始めたリーディング（統計で同じカードを二重に数えないため） */
  fromDaily?: boolean;
}

export interface Settings {
  allowReversed: boolean;
  persona: PersonaId;
}

const KEYS = { daily: "tarot.daily", readings: "tarot.readings", settings: "tarot.settings" };

function load<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

function save(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // プライベートブラウズなどで保存できない場合は何もしない
  }
}

export function todayString(d = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export const loadDaily = () => load<DailyRecord[]>(KEYS.daily, []);
export const saveDaily = (records: DailyRecord[]) => save(KEYS.daily, records);
export const loadReadings = () => load<ReadingRecord[]>(KEYS.readings, []);
export const saveReadings = (records: ReadingRecord[]) => save(KEYS.readings, records.slice(0, 200));
export const loadSettings = () => ({ allowReversed: true, persona: "mystic" as PersonaId, ...load<Partial<Settings>>(KEYS.settings, {}) });
export const saveSettings = (s: Settings) => save(KEYS.settings, s);

/** 今日まで（今日が未実施なら昨日まで）何日連続で1枚引きをしたか */
export function streak(records: DailyRecord[]): number {
  const dates = new Set(records.map((r) => r.date));
  const d = new Date();
  if (!dates.has(todayString(d))) d.setDate(d.getDate() - 1);
  let count = 0;
  while (dates.has(todayString(d))) {
    count++;
    d.setDate(d.getDate() - 1);
  }
  return count;
}
