import { useEffect, useState } from "react";
import type { DrawnCard } from "../shared/cards.ts";
import type { PersonaId } from "../shared/personas.ts";
import { Daily } from "./components/Daily.tsx";
import { History } from "./components/History.tsx";
import { NewReading } from "./components/NewReading.tsx";
import { ReadingSession } from "./components/ReadingSession.tsx";
import {
  type DailyRecord,
  loadDaily,
  loadReadings,
  loadSettings,
  type ReadingRecord,
  saveDaily,
  saveReadings,
  saveSettings,
  type Settings,
} from "./storage.ts";

type Tab = "daily" | "reading" | "history";

export default function App() {
  const [tab, setTab] = useState<Tab>("daily");
  const [daily, setDaily] = useState<DailyRecord[]>(loadDaily);
  const [readings, setReadings] = useState<ReadingRecord[]>(loadReadings);
  const [settings, setSettings] = useState<Settings>(loadSettings);
  const [active, setActive] = useState<{ record: ReadingRecord; fresh: boolean } | null>(null);
  const [aiConfigured, setAiConfigured] = useState(true);

  useEffect(() => saveDaily(daily), [daily]);
  useEffect(() => saveReadings(readings), [readings]);
  useEffect(() => saveSettings(settings), [settings]);
  useEffect(() => {
    fetch("/api/health")
      .then((r) => r.json())
      .then((h) => setAiConfigured(Boolean(h.aiConfigured)))
      .catch(() => setAiConfigured(false));
  }, []);

  const startSession = (params: { question: string; spreadId: string; persona: PersonaId; cards: DrawnCard[]; fromDaily?: boolean }, fresh: boolean) => {
    const record: ReadingRecord = { id: crypto.randomUUID(), createdAt: new Date().toISOString(), messages: [], ...params };
    setActive({ record, fresh });
    setTab("reading");
  };

  const updateRecord = (record: ReadingRecord) => {
    setActive((a) => (a && a.record.id === record.id ? { ...a, record } : a));
    // AIの回答が1つ以上ついたものだけ履歴に残す
    if (record.messages.length === 0) return;
    setReadings((rs) => [record, ...rs.filter((r) => r.id !== record.id)]);
  };

  const tabs: { id: Tab; label: string; icon: string }[] = [
    { id: "daily", label: "今日の1枚", icon: "☀" },
    { id: "reading", label: "占う", icon: "✦" },
    { id: "history", label: "記録", icon: "☾" },
  ];

  return (
    <div className="app">
      <header className="app-header">
        <h1 className="logo">星読みタロット</h1>
        <label className="toggle">
          <input type="checkbox" checked={settings.allowReversed} onChange={(e) => setSettings({ ...settings, allowReversed: e.target.checked })} />
          逆位置あり
        </label>
      </header>

      {!aiConfigured && <p className="banner">AIリーディングのサーバーにつながっていません。今日の1枚は使えます。</p>}

      <main className="app-main">
        {tab === "daily" && (
          <Daily
            records={daily}
            allowReversed={settings.allowReversed}
            onDraw={(r) => setDaily((d) => [...d.filter((x) => x.date !== r.date), r])}
            onAskAi={(card) => startSession({ question: "今日1日をどう過ごすとよいか", spreadId: "one", persona: settings.persona, cards: [card], fromDaily: true }, false)}
          />
        )}
        {/* 占いの途中でタブを移動してもストリーミングや状態が消えないよう、常に描画して隠す */}
        <div hidden={tab !== "reading"}>
          {active ? (
            <ReadingSession key={active.record.id} record={active.record} startFaceDown={active.fresh} onUpdate={updateRecord} onNew={() => setActive(null)} />
          ) : (
            <NewReading
              persona={settings.persona}
              allowReversed={settings.allowReversed}
              onPersonaChange={(persona) => setSettings({ ...settings, persona })}
              onComplete={(params) => startSession(params, true)}
            />
          )}
        </div>
        {tab === "history" && (
          <History
            daily={daily}
            readings={readings}
            onOpen={(record) => {
              setActive({ record, fresh: false });
              setTab("reading");
            }}
            onDelete={(id) => {
              setReadings((rs) => rs.filter((r) => r.id !== id));
              if (active?.record.id === id) setActive(null);
            }}
          />
        )}
      </main>

      <nav className="tabbar">
        {tabs.map((t) => (
          <button type="button" key={t.id} className={`tab ${tab === t.id ? "is-active" : ""}`} onClick={() => setTab(t.id)}>
            <span className="tab-icon">{t.icon}</span>
            {t.label}
          </button>
        ))}
      </nav>
    </div>
  );
}
