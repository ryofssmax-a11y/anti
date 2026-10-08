(() => {
'use strict';

/* ---------- utils ---------- */
const $ = (s, el = document) => el.querySelector(s);
const pad = (n) => String(n).padStart(2, '0');
const dkey = (d = new Date()) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const dnum = (d = new Date()) => Math.floor(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 864e5);
const parseKey = (k) => { const [y, m, d] = k.split('-').map(Number); return new Date(y, m - 1, d); };
const rnd = (n) => Math.floor(Math.random() * n);
const pick = (a) => a[rnd(a.length)];
const shuffle = (a) => { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = rnd(i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const norm = (s) => s.toLowerCase().replace(/[^a-z0-9\- ]/g, '').replace(/\s+/g, ' ').trim();
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function lev(a, b) {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++)
    d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
  return d[a.length][b.length];
}

/* ---------- state ---------- */
const KEY = 'belajar-v1';
const fresh = () => ({
  xp: 0, coins: 0, streak: 0, best: 0, lastDay: null, freezes: 1, goal: 50,
  days: {}, daily: { date: '', xp: 0, lessons: 0, correct: 0, maxCombo: 0, chest: false, quests: {} },
  words: {}, units: {}, badges: {}, sound: true,
  stats: { lessons: 0, perfect: 0, maxCombo: 0, correct: 0, chests: 0 },
});
let S;
try { S = Object.assign(fresh(), JSON.parse(localStorage.getItem(KEY) || '{}')); } catch (e) { S = fresh(); }
const save = () => { try { localStorage.setItem(KEY, JSON.stringify(S)); } catch (e) { /* private mode etc. */ } };

function rollDay() {
  if (S.daily.date !== dkey()) S.daily = { date: dkey(), xp: 0, lessons: 0, correct: 0, maxCombo: 0, chest: false, quests: {} };
}
function resolveStreak() {
  rollDay();
  if (!S.lastDay || S.streak === 0) return;
  const diff = dnum() - dnum(parseKey(S.lastDay));
  if (diff >= 2) {
    const missed = diff - 1;
    if (S.freezes >= missed) {
      S.freezes -= missed;
      const y = new Date(); y.setDate(y.getDate() - 1);
      S.lastDay = dkey(y);
      setTimeout(() => toast(`🧊 ストリークフリーズで ${S.streak}日連続を守りました！`), 600);
    } else { S.streak = 0; }
  }
}
const level = (xp) => Math.floor(Math.sqrt(xp / 50)) + 1;
const levelStart = (l) => 50 * (l - 1) * (l - 1);
const titleOf = (l) => TITLES[Math.min(l - 1, TITLES.length - 1)];

function addXP(n) {
  rollDay();
  S.xp += n; S.daily.xp += n;
  S.days[dkey()] = (S.days[dkey()] || 0) + n;
  if (S.lastDay !== dkey()) {
    const y = new Date(); y.setDate(y.getDate() - 1);
    S.streak = S.lastDay === dkey(y) ? S.streak + 1 : 1;
    S.best = Math.max(S.best, S.streak);
    S.lastDay = dkey();
  }
}

/* ---------- SRS ---------- */
const INTERVALS = [0, 1, 3, 7, 14, 30];
const W = (id) => S.words[id] || (S.words[id] = { box: 0, due: 0, seen: false });
function grade(id, ok) {
  const w = W(id);
  w.seen = true;
  w.box = ok ? Math.min(5, w.box + 1) : 0;
  w.due = dnum() + INTERVALS[w.box];
}
const dueItems = () => ALL.filter((i) => S.words[i.id] && S.words[i.id].seen && S.words[i.id].due <= dnum());
const learnedCount = () => ALL.filter((i) => S.words[i.id] && S.words[i.id].box >= 2).length;
const unitIdx = (id) => UNITS.findIndex((u) => u.id === id);
const crowns = (u) => Math.min(5, (S.units[u.id] || 0));
const unlocked = (i) => i === 0 || (S.units[UNITS[i - 1].id] || 0) >= 1;

/* ---------- sound / speech / fx ---------- */
let AC;
function tone(f, dur = 0.12, type = 'sine', vol = 0.12, at = 0) {
  if (!S.sound) return;
  try {
    AC = AC || new (window.AudioContext || window.webkitAudioContext)();
    const o = AC.createOscillator(), g = AC.createGain(), t = AC.currentTime + at;
    o.type = type; o.frequency.value = f; o.connect(g); g.connect(AC.destination);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.start(t); o.stop(t + dur);
  } catch (e) { /* no audio */ }
}
const sfx = {
  ok(c) { const b = 523 * Math.pow(1.06, Math.min(c, 12)); tone(b, 0.1, 'triangle'); tone(b * 1.5, 0.16, 'triangle', 0.12, 0.08); },
  bad() { tone(180, 0.25, 'sawtooth', 0.09); },
  coin() { tone(988, 0.07, 'square', 0.06); tone(1319, 0.18, 'square', 0.06, 0.07); },
  win() { [523, 659, 784, 1047].forEach((f, i) => tone(f, 0.22, 'triangle', 0.13, i * 0.1)); },
  big() { [523, 659, 784, 1047, 1319, 1568].forEach((f, i) => tone(f, 0.28, 'triangle', 0.14, i * 0.09)); },
};
const buzz = (p) => { try { S.sound && navigator.vibrate && navigator.vibrate(p); } catch (e) { /* noop */ } };

let idVoice = null;
function loadVoices() {
  if (!('speechSynthesis' in window)) return;
  idVoice = speechSynthesis.getVoices().find((v) => /^id([-_]|$)/i.test(v.lang)) || null;
}
if ('speechSynthesis' in window) { loadVoices(); speechSynthesis.onvoiceschanged = loadVoices; }
let voiceWarned = false;
function speak(text, rate = 0.9) {
  if (!('speechSynthesis' in window)) { toast('このブラウザは音声読み上げに対応していません'); return; }
  try {
    loadVoices();
    if (!idVoice && !voiceWarned) { voiceWarned = true; toast('インドネシア語の音声が見つかりません。端末の設定で音声を追加すると正しい発音で聞けます'); }
    const ss = speechSynthesis;
    ss.cancel(); ss.resume();
    setTimeout(() => {
      const u = new SpeechSynthesisUtterance(text);
      u.lang = 'id-ID'; u.rate = rate; u.volume = 1; if (idVoice) u.voice = idVoice;
      u.onerror = (e) => { if (e.error && e.error !== 'interrupted' && e.error !== 'canceled') toast('音声を再生できませんでした（' + e.error + '）'); };
      ss.speak(u);
    }, 60);
  } catch (e) { toast('音声を再生できませんでした'); }
}

const fx = $('#fx'), fctx = fx.getContext('2d');
let parts = [], raf = 0;
function confetti(n = 140, y = 0.35) {
  fx.width = innerWidth; fx.height = innerHeight;
  const cols = ['#e63946', '#ffb703', '#2bb673', '#118ab2', '#8338ec', '#fff'];
  for (let i = 0; i < n; i++) parts.push({ x: innerWidth / 2, y: innerHeight * y, vx: (Math.random() - 0.5) * 16, vy: -Math.random() * 15 - 3, s: 5 + Math.random() * 7, c: pick(cols), r: Math.random() * 6, vr: (Math.random() - 0.5) * 0.4, life: 90 + rnd(50) });
  if (!raf) raf = requestAnimationFrame(tick);
}
function tick() {
  fctx.clearRect(0, 0, fx.width, fx.height);
  parts = parts.filter((p) => p.life-- > 0);
  parts.forEach((p) => {
    p.vy += 0.45; p.x += p.vx; p.y += p.vy; p.r += p.vr;
    fctx.save(); fctx.translate(p.x, p.y); fctx.rotate(p.r); fctx.fillStyle = p.c; fctx.globalAlpha = Math.min(1, p.life / 25);
    fctx.fillRect(-p.s / 2, -p.s / 3, p.s, p.s * 0.6); fctx.restore();
  });
  raf = parts.length ? requestAnimationFrame(tick) : 0;
  if (!raf) fctx.clearRect(0, 0, fx.width, fx.height);
}
let toastT;
function toast(msg) {
  const t = $('#toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('show'), 2600);
}
function floatText(txt, el) {
  const r = (el || document.body).getBoundingClientRect();
  const f = document.createElement('div'); f.className = 'float'; f.textContent = txt;
  f.style.left = (el ? r.left + r.width / 2 - 20 : innerWidth / 2 - 20) + 'px'; f.style.top = (el ? r.top : innerHeight / 2) + 'px';
  document.body.appendChild(f); setTimeout(() => f.remove(), 1000);
}

/* ---------- modal (queue) ---------- */
function modal({ em, title, text, btn = 'やったー！', rare = false, html = '' }) {
  return new Promise((res) => {
    const m = $('#modal');
    m.hidden = false;
    m.innerHTML = `<div class="mbox ${rare ? 'rare' : ''}"><span class="em">${em}</span><h2>${title}</h2><p>${text || ''}</p>${html}<button class="btn ${rare ? 'gold' : ''}" id="mok">${btn}</button></div>`;
    $('#mok').onclick = () => { m.hidden = true; m.innerHTML = ''; res(); };
  });
}

function confirmModal(text, yes = 'はい', no = 'キャンセル') {
  return new Promise((res) => {
    const m = $('#modal');
    m.hidden = false;
    m.innerHTML = `<div class="mbox"><p style="color:var(--ink);font-weight:700">${text}</p><button class="btn red" id="myes">${yes}</button><button class="btn ghost" id="mno" style="margin-top:10px">${no}</button></div>`;
    const done = (v) => { m.hidden = true; m.innerHTML = ''; res(v); };
    $('#myes').onclick = () => done(true); $('#mno').onclick = () => done(false);
  });
}

/* ---------- daily quests / badges / chest ---------- */
const QPOOL = [
  [{ id: 'l1', t: 'レッスンを1回完了する', goal: 1, get: (d) => d.lessons, r: 10 }, { id: 'l2', t: 'レッスンを2回完了する', goal: 2, get: (d) => d.lessons, r: 20 }],
  [{ id: 'c5', t: '5コンボを達成する', goal: 5, get: (d) => d.maxCombo, r: 15 }, { id: 'c8', t: '8コンボを達成する', goal: 8, get: (d) => d.maxCombo, r: 25 }],
  [{ id: 'a20', t: '20問正解する', goal: 20, get: (d) => d.correct, r: 20 }, { id: 'a30', t: '30問正解する', goal: 30, get: (d) => d.correct, r: 30 }],
];
const todaysQuests = () => QPOOL.map((p, i) => p[(dnum() + i) % 2]);
function claimQuests() {
  const got = [];
  todaysQuests().forEach((q) => {
    if (q.get(S.daily) >= q.goal && !S.daily.quests[q.id]) { S.daily.quests[q.id] = true; S.coins += q.r; got.push(q); }
  });
  return got;
}
const BADGES = [
  { id: 'first', em: '🌱', name: 'はじめの一歩', desc: '初めてレッスンを完了', ok: () => S.stats.lessons >= 1 },
  { id: 'early', em: '🌅', name: 'Selamat pagi!', desc: '朝5〜9時に学習', ok: () => { const h = new Date().getHours(); return S.stats.lessons >= 1 && h >= 5 && h < 9; } },
  { id: 'perfect', em: '💎', name: 'ノーミス', desc: 'ミスなしでレッスン完了', ok: () => S.stats.perfect >= 1 },
  { id: 'combo10', em: '⚡', name: 'コンボ10', desc: '10連続正解', ok: () => S.stats.maxCombo >= 10 },
  { id: 's3', em: '🔥', name: '3日連続', desc: '3日連続で学習', ok: () => S.streak >= 3 },
  { id: 's7', em: '🏅', name: '1週間連続', desc: '7日連続で学習', ok: () => S.streak >= 7 },
  { id: 's30', em: '👑', name: '30日連続', desc: '30日連続で学習', ok: () => S.streak >= 30 },
  { id: 'w20', em: '📚', name: '20語マスター', desc: '20語をしっかり記憶', ok: () => learnedCount() >= 20 },
  { id: 'w50', em: '🎓', name: '50語マスター', desc: '50語をしっかり記憶', ok: () => learnedCount() >= 50 },
  { id: 'lv5', em: '⭐', name: 'レベル5', desc: 'レベル5に到達', ok: () => level(S.xp) >= 5 },
  { id: 'chest', em: '🎁', name: '宝箱ハンター', desc: '宝箱を初めて開ける', ok: () => S.stats.chests >= 1 },
  { id: 'all', em: '🏆', name: 'コンプリート', desc: '全ユニットを5冠', ok: () => UNITS.every((u) => crowns(u) >= 5) },
];
function checkBadges() {
  const got = [];
  BADGES.forEach((b) => { if (!S.badges[b.id] && b.ok()) { S.badges[b.id] = Date.now(); got.push(b); } });
  return got;
}

/* ---------- Android: 音声に対応したブラウザへの誘導 ---------- */
const OPEN_URL = window.BELAJAR_URL || location.href;
const isAndroid = /Android/i.test(navigator.userAgent);
const isWebView = /; wv\)/.test(navigator.userAgent) || (/Android/.test(navigator.userAgent) && /Version\/\d+\.\d+ Chrome\//.test(navigator.userAgent));
let hintHidden = false;
try { hintHidden = sessionStorage.getItem('belajar-hint') === '1'; } catch (e) { /* noop */ }
const needBrowserHint = () => isAndroid && !hintHidden && (!('speechSynthesis' in window) || isWebView);
function chromeIntent() {
  const m = /^https?:\/\/([^#]*)/.exec(OPEN_URL);
  return m ? `intent://${m[1]}#Intent;scheme=https;package=com.android.chrome;S.browser_fallback_url=${encodeURIComponent(OPEN_URL)};end` : '';
}

/* ---------- views ---------- */
const view = $('#view');
let tab = 'home';

function renderTop() {
  rollDay();
  const l = level(S.xp), a = levelStart(l), b = levelStart(l + 1);
  const pct = Math.round(((S.xp - a) / (b - a)) * 100);
  const hot = S.streak > 0 && S.lastDay === dkey();
  $('#top').innerHTML = `<div class="hrow">
    <div class="pill ${hot ? 'fire' : 'off'}">${hot ? '🔥' : '🕯️'} ${S.streak}</div>
    <div class="lvl"><small><span>Lv.${l} ${titleOf(l)}</span><span>あと${b - S.xp}XP</span></small><div class="mini"><i style="width:${pct}%"></i></div></div>
    <div class="pill">🪙 ${S.coins}</div></div>`;
}
function renderNav() {
  const due = dueItems().length;
  const t = [['home', '🏠', 'ホーム'], ['review', '🔁', '復習'], ['dict', '📖', 'フレーズ'], ['me', '🏆', '実績']];
  $('#nav').innerHTML = '<div class="in">' + t.map(([k, e, n]) => `<button data-act="tab" data-tab="${k}" class="${tab === k ? 'on' : ''}"><b>${e}</b>${n}${k === 'review' && due ? `<span class="dot">${due}</span>` : ''}</button>`).join('') + '</div>';
}
function ring(pct, label, done) {
  const c = 2 * Math.PI * 36;
  return `<div class="ring ${done ? 'done' : ''}"><svg width="84" height="84" viewBox="0 0 84 84"><circle class="bg" cx="42" cy="42" r="36"/><circle class="fg" cx="42" cy="42" r="36" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - Math.min(1, pct))}"/></svg><span>${label}</span></div>`;
}
function hoursLeft() { const n = new Date(), e = new Date(n); e.setHours(24, 0, 0, 0); return Math.max(1, Math.ceil((e - n) / 36e5)); }

function renderHome() {
  rollDay();
  const d = S.daily, done = d.xp >= S.goal;
  const rem = Math.max(0, S.goal - d.xp);
  let msg = done ? '🎉 今日の目標達成！' : d.xp === 0 ? 'まずは1レッスンやってみよう' : rem <= 20 ? `あとたったの ${rem}XP！` : `あと ${rem}XP で目標達成`;
  const week = [];
  for (let i = 6; i >= 0; i--) { const x = new Date(); x.setDate(x.getDate() - i); const k = dkey(x); week.push({ k, on: (S.days[k] || 0) > 0, today: i === 0, w: '日月火水木金土'[x.getDay()] }); }
  const risk = S.streak > 0 && d.xp === 0;
  const due = dueItems().length;
  const nextU = UNITS.findIndex((u, i) => unlocked(i) && crowns(u) < 1);
  const chestReady = done && !d.chest;
  const qs = todaysQuests();
  const intent = chromeIntent();
  view.innerHTML = `
    ${needBrowserHint() ? `<div class="card warn"><b>🔊 発音を聞くには Chrome で開いてください</b><div class="muted" style="color:inherit;margin:4px 0 8px">このブラウザ（アプリ内ブラウザ）では音声が出ない場合があります。</div><div class="row" style="flex-wrap:wrap;gap:8px">${intent ? `<a class="btn gold sm" href="${intent}" target="_blank" rel="noopener" style="text-decoration:none">Chromeで開く</a>` : ''}<button class="btn ghost sm" data-act="copyurl">URLをコピー</button><button class="link" data-act="hidehint">閉じる</button></div></div>` : ''}
    ${risk ? `<div class="card warn"><b>🔥 ${S.streak}日連続が途切れそう！</b><div class="muted" style="color:inherit">今日はあと約${hoursLeft()}時間。1レッスンで守れます${S.freezes ? `（🧊フリーズ×${S.freezes}）` : ''}。</div></div>` : ''}
    <div class="card"><div class="row">${ring(d.xp / S.goal, `${d.xp}<br>/${S.goal}`, done)}<div class="grow"><h3>今日の目標</h3><div class="muted">${msg}</div>
      ${chestReady ? '<button class="btn gold sm" style="margin-top:8px" data-act="chest">🎁 宝箱を開ける！</button>' : d.chest ? '<div class="muted" style="margin-top:6px">🎁 今日の宝箱は開封済み</div>' : '<div class="muted" style="margin-top:6px">🎁 達成すると宝箱が開きます</div>'}</div></div>
      <div class="week">${week.map((w) => `<div class="wd ${w.on ? 'on' : ''} ${w.today ? 'today' : ''}"><i>${w.on ? '🔥' : ''}</i>${w.w}</div>`).join('')}</div></div>
    ${due ? `<div class="card"><div class="row"><div class="grow"><h3>🔁 復習の時間です</h3><div class="muted">${due}語が忘れかけています。サクッと復習しよう。</div></div><button class="btn red sm" data-act="review">復習</button></div></div>` : ''}
    <div class="card"><h3>📜 今日のクエスト</h3>${qs.map((q) => { const v = Math.min(q.goal, q.get(d)); const ok = !!d.quests[q.id]; return `<div class="quest ${ok ? 'ok' : ''}"><div class="t">${ok ? '✅ ' : ''}${q.t}<div class="mini"><i style="width:${(v / q.goal) * 100}%"></i></div></div><div class="rw">${v}/${q.goal}<br>🪙+${q.r}</div></div>`; }).join('')}</div>
    <div class="path">${UNITS.map((u, i) => {
      const ok = unlocked(i), c = crowns(u);
      return `<div class="node">${i === nextU ? '<span class="tag">スタート！</span>' : ''}<button class="bubble ${ok ? '' : 'lock'} ${i === nextU ? 'next' : ''}" style="background:${u.color}" data-act="unit" data-u="${u.id}" ${ok ? '' : 'disabled'}>${ok ? u.icon : '🔒'}<span class="crowns">${'★'.repeat(c)}${'☆'.repeat(5 - c)}</span></button><b>${u.name}</b><small>${u.sub} ・ ${u.items.length}フレーズ</small></div>`;
    }).join('')}</div>`;
}

function renderReview() {
  const due = dueItems(), seen = ALL.filter((i) => S.words[i.id] && S.words[i.id].seen);
  const weak = seen.filter((i) => S.words[i.id].box <= 1);
  view.innerHTML = `<div class="card"><h3>🔁 復習</h3><p class="muted">忘れかけた頃にもう一度。<b>間隔をあけて思い出す</b>のが、記憶に一番効きます。</p>
    <div class="stats"><div class="stat"><b>${due.length}</b>復習の時期</div><div class="stat"><b>${weak.length}</b>まだ苦手</div></div><br>
    <button class="btn red" data-act="review" ${seen.length ? '' : 'disabled'}>${seen.length ? '復習をはじめる' : 'まずはレッスンを1つやろう'}</button></div>`;
}

function renderDict() {
  view.innerHTML = `<input class="search" id="q" placeholder="🔍 検索（日本語・Indonesia語）"><div id="dl"></div>`;
  const draw = (q = '') => {
    q = q.toLowerCase();
    $('#dl').innerHTML = UNITS.map((u) => {
      const its = u.items.filter((i) => !q || (i.id_ + i.ja + i.kana).toLowerCase().includes(q));
      if (!its.length) return '';
      return `<div class="card"><h3>${u.icon} ${u.name}</h3>${its.map((i) => {
        const w = S.words[i.id], m = w && w.seen ? (w.box >= 4 ? 3 : w.box >= 2 ? 2 : 1) : 0;
        return `<button class="li" data-act="say" data-t="${i.id_.replace(/"/g, '')}"><span class="mastery m${m}"></span><span class="grow"><span class="a">${i.id_}</span> <span class="b">${i.kana}</span><br><span class="c">${i.ja}</span></span>🔊</button>`;
      }).join('')}</div>`;
    }).join('') || '<p class="muted">見つかりませんでした</p>';
  };
  draw();
  $('#q').oninput = (e) => draw(e.target.value);
}

function renderMe() {
  const mastered = learnedCount(), seen = ALL.filter((i) => S.words[i.id] && S.words[i.id].seen).length;
  view.innerHTML = `
    <div class="stats" style="margin-top:12px">
      <div class="stat"><b>🔥 ${S.streak}日</b>連続（最長 ${S.best}日）</div>
      <div class="stat"><b>⭐ ${S.xp}</b>累計XP</div>
      <div class="stat"><b>📚 ${mastered}/${ALL.length}</b>定着した語（見た語 ${seen}）</div>
      <div class="stat"><b>🧊 ${S.freezes}</b>ストリークフリーズ</div></div>
    <div class="card"><div class="row"><div class="grow"><b>🧊 ストリークフリーズ</b><div class="muted">1日休んでも連続記録を守れます（最大3個）</div></div><button class="btn gold sm" data-act="freeze">🪙50</button></div></div>
    <div class="card"><h3>🏅 バッジ（${Object.keys(S.badges).length}/${BADGES.length}）</h3><div class="badges">${BADGES.map((b) => `<div class="bd ${S.badges[b.id] ? '' : 'lock'}"><b>${b.em}</b>${b.name}<br><span class="muted" style="font-size:11px">${b.desc}</span></div>`).join('')}</div></div>
    <div class="card"><h3>⚙️ 設定</h3><div class="muted">1日の目標XP</div><div class="seg" style="margin:6px 0 12px">${[30, 50, 100].map((g) => `<button data-act="goal" data-g="${g}" class="${S.goal === g ? 'on' : ''}">${g}XP</button>`).join('')}</div>
      <button class="btn ghost" data-act="sound">${S.sound ? '🔊 効果音：ON' : '🔇 効果音：OFF'}</button>
      <p style="text-align:center;margin:14px 0 0"><button class="link" data-act="reset">学習データをリセット</button></p></div>`;
}

function render() {
  resolveStreak(); renderTop(); renderNav();
  ({ home: renderHome, review: renderReview, dict: renderDict, me: renderMe })[tab]();
}

/* ---------- lesson engine ---------- */
let L = null;
const lesson = $('#lesson');

function startSession(kind, unit) {
  let pool, intro = [];
  if (kind === 'review') {
    const due = dueItems(), seen = ALL.filter((i) => S.words[i.id] && S.words[i.id].seen);
    pool = shuffle(due.length >= 6 ? due : due.concat(shuffle(seen.filter((i) => !due.includes(i))).sort((a, b) => S.words[a.id].box - S.words[b.id].box)).slice(0, Math.max(due.length, 8)));
    pool = pool.slice(0, 10);
  } else {
    const sorted = shuffle(unit.items).sort((a, b) => (S.words[a.id] ? S.words[a.id].box : -1) - (S.words[b.id] ? S.words[b.id].box : -1));
    pool = sorted.slice(0, 8);
    intro = pool.filter((i) => !(S.words[i.id] && S.words[i.id].seen)).slice(0, 5);
  }
  const canListen = !!idVoice;
  const qs = pool.map((it) => {
    const box = S.words[it.id] ? S.words[it.id].box : 0, multi = it.id_.trim().split(/\s+/).length >= 2;
    const t = [];
    if (box <= 0) { t.push('choose'); canListen && t.push('listen'); }
    else if (box === 1) { t.push('rev'); multi && t.push('order'); canListen && t.push('listen'); }
    else { t.push('rev'); t.push('type'); multi && t.push('order'); }
    return { type: pick(t), it };
  });
  const dialogs = unit ? shuffle(unit.dialogs).slice(0, 2) : [];
  if (qs.length >= 5) qs.splice(Math.min(5, qs.length), 0, { type: 'match', items: shuffle(pool).slice(0, 5) });
  dialogs.forEach((dl, i) => qs.splice(Math.min(qs.length, 3 + i * 4), 0, { type: 'reply', dl }));
  L = {
    kind, unit, qs, i: 0, intro, ii: 0, combo: 0, maxCombo: 0, correct: 0, wrong: 0, xp: 0, retried: new Set(),
    lv0: level(S.xp), goal0: S.daily.xp >= S.goal, streak0: S.streak, today0: S.lastDay === dkey(), newWords: intro.length, total: qs.length,
  };
  lesson.hidden = false;
  document.body.style.overflow = 'hidden';
  intro.length ? showIntro() : showQ();
}

function frame(inner, extra = '') {
  const pct = L ? Math.round((L.i / L.qs.length) * 100) : 0;
  lesson.innerHTML = `<div class="lw"><div class="lhead"><button class="x" data-act="quit" aria-label="閉じる">✕</button><div class="mini"><i style="width:${pct}%"></i></div><div class="combo ${L.combo >= 3 ? 'hot' : ''}" id="cb">${L.combo >= 2 ? `🔥${L.combo}` : '　'}</div></div><div id="stage">${inner}</div></div>${extra}<div class="sheet" id="sheet"></div>`;
  lesson.scrollTop = 0;
}

function showIntro() {
  const it = L.intro[L.ii], last = L.ii === L.intro.length - 1;
  frame(`<div class="q">新しい表現 ${L.ii + 1}/${L.intro.length}</div>
    <div class="flash"><span class="new">NEW</span><div class="big">${it.id_}</div><div class="kana">${it.kana}</div>
    <button class="spk big" data-act="say" data-t="${it.id_}" aria-label="発音">🔊</button><div class="ja">${it.ja}</div>${it.note ? `<div class="note">💡 ${it.note}</div>` : ''}</div>`,
    `<div class="chk"><button class="btn" id="go">${last ? 'クイズへ！' : 'つぎへ'}</button></div>`);
  W(it.id).seen = true; save();
  $('#go').onclick = () => { L.ii++; L.ii >= L.intro.length ? showQ() : showIntro(); };
  setTimeout(() => speak(it.id_), 250);
}

function showQ() {
  if (L.i >= L.qs.length) return finish();
  const q = L.qs[L.i];
  ({ choose: qChoose, rev: qChoose, listen: qChoose, reply: qChoose, order: qOrder, type: qType, match: qMatch })[q.type](q);
}

function others(it, n, key) {
  const same = shuffle(UNITS[unitIdx(it.unit)].items.filter((x) => x.id !== it.id && x[key] !== it[key]));
  const rest = shuffle(ALL.filter((x) => x.id !== it.id && x[key] !== it[key] && !same.includes(x)));
  return same.concat(rest).filter((x, i, a) => a.findIndex((y) => y[key] === x[key]) === i).slice(0, n);
}

function qChoose(q) {
  let head, opts, answer, label = '日本語に合うものを選ぼう';
  if (q.type === 'choose') {
    answer = q.it.ja; opts = shuffle([q.it].concat(others(q.it, 3, 'ja'))).map((x) => x.ja);
    head = `<div class="prompt"><button class="spk" data-act="say" data-t="${q.it.id_}">🔊</button><span>${q.it.id_}<span class="kana">${q.it.kana}</span></span></div>`;
    label = 'どういう意味？';
  } else if (q.type === 'rev') {
    answer = q.it.id_; opts = shuffle([q.it].concat(others(q.it, 3, 'id_'))).map((x) => x.id_);
    head = `<div class="prompt">${q.it.ja}</div>`; label = 'インドネシア語で言うと？';
  } else if (q.type === 'listen') {
    answer = q.it.ja; opts = shuffle([q.it].concat(others(q.it, 3, 'ja'))).map((x) => x.ja);
    head = `<div style="text-align:center"><button class="spk big" data-act="say" data-t="${q.it.id_}">🔊</button><div><button class="link" data-act="slow" data-t="${q.it.id_}">🐢 ゆっくり聞く</button></div></div>`; label = '聞こえた言葉の意味は？';
    setTimeout(() => speak(q.it.id_), 300);
  } else {
    answer = q.dl.a; opts = shuffle([q.dl.a].concat(q.dl.wrong));
    head = `<div class="say"><button class="spk" data-act="say" data-t="${q.dl.q}">🔊</button><div><div class="t">${q.dl.q}</div><div class="muted">${q.dl.qja}</div></div></div>`; label = '💬 返事はどれ？';
    setTimeout(() => speak(q.dl.q), 300);
  }
  frame(`<div class="q">${label}</div>${head}<div class="opts">${opts.map((o, i) => `<button class="opt" data-i="${i}">${o}</button>`).join('')}</div>`);
  const bs = [...lesson.querySelectorAll('.opt')];
  bs.forEach((b) => b.onclick = () => {
    const ok = b.textContent === answer;
    bs.forEach((x) => { x.disabled = true; if (x.textContent === answer) x.classList.add('ok'); });
    if (!ok) b.classList.add('bad');
    if (q.type === 'rev' || q.type === 'reply') speak(answer);
    resolve(q, ok, answer, b);
  });
}

function qOrder(q) {
  const ans = q.it.id_.split(' '), have = new Set(ans.map(norm));
  const extra = shuffle(ALL.flatMap((x) => x.id_.split(' ')).filter((w) => !have.has(norm(w)) && norm(w).length > 1 && w.length < 9)).filter((w, i, a) => a.indexOf(w) === i).slice(0, 2);
  const tiles = shuffle(ans.concat(extra));
  frame(`<div class="q">正しい順に並べよう</div><div class="prompt">${q.it.ja}</div><div class="line" id="line"></div><div class="bank" id="bank">${tiles.map((w, i) => `<button class="tile" data-i="${i}">${w}</button>`).join('')}</div>`,
    '<div class="chk"><button class="btn" id="chk" disabled>チェック</button></div>');
  const line = $('#line'), bank = $('#bank'), chk = $('#chk');
  const chosen = [];
  const sync = () => { chk.disabled = !chosen.length; };
  bank.querySelectorAll('.tile').forEach((t) => t.onclick = () => {
    const c = t.cloneNode(true); t.classList.add('used'); line.appendChild(c); chosen.push(t); sync(); tone(660, 0.05, 'triangle', 0.06);
    c.onclick = () => { if (chk.dataset.done) return; c.remove(); t.classList.remove('used'); chosen.splice(chosen.indexOf(t), 1); sync(); };
  });
  chk.onclick = () => {
    chk.dataset.done = 1;
    const ok = chosen.map((t) => norm(t.textContent)).join(' ') === ans.map(norm).join(' ');
    chk.parentElement.remove(); speak(q.it.id_);
    resolve(q, ok, q.it.id_);
  };
}

function qType(q) {
  const a = q.it.id_;
  frame(`<div class="q">インドネシア語で書いてみよう</div><div class="prompt">${q.it.ja}</div><input class="inp" id="inp" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="ここに入力"><div class="hint">ヒント：${a[0]}… （${a.length}文字）</div>`,
    '<div class="chk"><button class="btn" id="chk" disabled>チェック</button></div>');
  const inp = $('#inp'), chk = $('#chk');
  inp.focus();
  inp.oninput = () => { chk.disabled = !inp.value.trim(); };
  const go = () => {
    if (chk.disabled || chk.dataset.done) return; chk.dataset.done = 1;
    const u = norm(inp.value), t = norm(a), d = lev(u, t);
    const ok = d === 0, near = !ok && d === 1 && t.length >= 6;
    chk.parentElement.remove(); inp.disabled = true; speak(a);
    resolve(q, ok || near, a, null, near ? 'おしい！スペルに注意 +' : '');
  };
  chk.onclick = go; inp.onkeydown = (e) => { if (e.key === 'Enter') go(); };
}

function qMatch(q) {
  const L1 = shuffle(q.items), R1 = shuffle(q.items);
  frame(`<div class="q">ペアを見つけよう</div><div class="match" id="mt">${L1.map((it, i) => `<button class="opt" data-k="${it.id}" data-s="l">${it.id_}</button><button class="opt" data-k="${R1[i].id}" data-s="r">${R1[i].ja}</button>`).join('')}</div>`);
  const mt = $('#mt');
  let sel = null, left = q.items.length, errs = 0;
  mt.querySelectorAll('.opt').forEach((b) => b.onclick = () => {
    if (b.classList.contains('gone')) return;
    if (!sel) { sel = b; b.classList.add('sel'); if (b.dataset.s === 'l') speak(b.textContent); return; }
    if (sel === b) { b.classList.remove('sel'); sel = null; return; }
    if (sel.dataset.s === b.dataset.s) { sel.classList.remove('sel'); sel = b; b.classList.add('sel'); return; }
    if (sel.dataset.k === b.dataset.k) {
      const a = sel; sel = null; sfx.coin(); buzz(15);
      [a, b].forEach((x) => { x.classList.remove('sel'); x.classList.add('ok'); setTimeout(() => x.classList.add('gone'), 350); });
      if (--left === 0) setTimeout(() => resolve(q, errs < 3, '', null, errs ? '' : 'パーフェクトマッチ！'), 450);
    } else {
      errs++; sel.classList.remove('sel'); sel.classList.add('bad'); b.classList.add('bad'); sfx.bad();
      const a = sel; sel = null; setTimeout(() => { a.classList.remove('bad'); b.classList.remove('bad'); }, 400);
    }
  });
}

function resolve(q, ok, answer, el, prefix = '') {
  const sheet = $('#sheet');
  let gain = 0;
  if (ok) {
    L.combo++; L.maxCombo = Math.max(L.maxCombo, L.combo); L.correct++;
    gain = 10 + (L.combo >= 3 ? Math.min(L.combo - 2, 5) * 2 : 0);
    L.xp += gain; addXP(gain); S.daily.correct++; S.stats.correct++;
    S.daily.maxCombo = Math.max(S.daily.maxCombo, L.combo); S.stats.maxCombo = Math.max(S.stats.maxCombo, L.combo);
    sfx.ok(L.combo); buzz(20);
    floatText('+' + gain, el || $('#cb'));
    const cb = $('#cb'); cb.textContent = L.combo >= 2 ? `🔥${L.combo}` : '　'; cb.classList.toggle('hot', L.combo >= 3); cb.classList.remove('pop'); void cb.offsetWidth; cb.classList.add('pop');
    if (L.combo === 5 || L.combo === 10) { confetti(60, 0.6); toast(L.combo === 5 ? '🔥 5コンボ！いい調子！' : '⚡ 10コンボ！！すごい！！'); }
  } else {
    L.combo = 0; L.wrong++; sfx.bad(); buzz([60, 40, 60]);
    $('#cb').textContent = '　'; $('#cb').classList.remove('hot');
    if (!L.retried.has(q) && q.type !== 'match') { L.retried.add(q); L.qs.push({ type: q.type === 'type' || q.type === 'order' ? 'rev' : q.type, it: q.it, dl: q.dl }); }
  }
  if (q.it) grade(q.it.id, ok);
  if (q.type === 'match') q.items.forEach((it) => grade(it.id, ok));
  save();
  const praise = ['せいかい！', 'ナイス！', 'すばらしい！', 'いいね！', 'Bagus!', 'Hebat!'];
  const note = q.it && q.it.note ? `<p>💡 ${q.it.note}</p>` : '';
  const ansLine = q.type === 'match' ? '' : q.it ? `<p><b>${q.it.id_}</b>（${q.it.kana}）＝ ${q.it.ja}</p>` : `<p><b>${answer}</b></p>`;
  sheet.className = 'sheet ' + (ok ? 'good' : 'bad');
  const head = ok ? (q.type === 'match' ? (prefix || 'マッチ完了！') : prefix || pick(praise)) + (gain ? ` +${gain}XP` : '') : prefix || 'おしい… 正解は';
  sheet.innerHTML = `<div class="in"><h4>${head}</h4>${ansLine}${note}<button class="btn" id="next">つづける</button></div>`;
  requestAnimationFrame(() => sheet.classList.add('show'));
  const next = () => { L.i++; document.removeEventListener('keydown', onKey); showQ(); };
  const onKey = (e) => { if (e.key === 'Enter' && $('#next')) { e.preventDefault(); next(); } };
  $('#next').onclick = next; setTimeout(() => document.addEventListener('keydown', onKey), 50);
  $('#next').focus();
}

async function finish() {
  const acc = Math.round((L.correct / Math.max(1, L.correct + L.wrong)) * 100), perfect = L.wrong === 0;
  const bonus = 20 + (perfect ? 20 : 0);
  L.xp += bonus; addXP(bonus);
  let lucky = 0;
  if (Math.random() < 0.3) { const r = Math.random(); lucky = r < 0.6 ? 1.5 : r < 0.9 ? 2 : 3; const extra = Math.round(L.xp * (lucky - 1)); L.xp += extra; addXP(extra); }
  const coins = Math.round(L.xp / 5); S.coins += coins;
  S.daily.lessons++; S.stats.lessons++; if (perfect) S.stats.perfect++;
  if (L.kind === 'unit') S.units[L.unit.id] = (S.units[L.unit.id] || 0) + 1;
  const quests = claimQuests(), badges = checkBadges();
  const goalNow = !L.goal0 && S.daily.xp >= S.goal, lv1 = level(S.xp);
  const firstToday = !L.today0, st = S.streak;
  let frz = false;
  if (firstToday && st > 0 && st % 7 === 0 && S.freezes < 3) { S.freezes++; frz = true; }
  save();
  sfx.win(); confetti(perfect ? 220 : 120);
  const stars = acc >= 90 ? 3 : acc >= 70 ? 2 : 1;
  lesson.innerHTML = `<div class="lw"><div class="result"><div class="stars">${[1, 2, 3].map((n) => `<span class="${n <= stars ? 'on' : ''}" style="animation-delay:${n * 0.2}s">⭐</span>`).join('')}</div>
    <h1 style="margin:6px 0 0">${perfect ? 'パーフェクト！💎' : 'レッスン完了！'}</h1><div class="muted">${L.kind === 'review' ? '復習' : L.unit.name}</div>
    <div class="rgrid"><div class="rbox xp"><small>獲得XP</small><span id="cxp">0</span></div><div class="rbox ac"><small>正確さ</small><span>${acc}%</span></div><div class="rbox cb"><small>最大コンボ</small><span>🔥${L.maxCombo}</span></div></div>
    <div id="luck"></div>
    <div class="chips"><span class="chip">🪙 +${coins}</span><span class="chip">${firstToday ? `🔥 ${st}日連続！` : `🔥 ${st}日連続中`}</span>${L.newWords ? `<span class="chip">🆕 新しい表現 ${L.newWords}個</span>` : ''}${S.daily.xp >= S.goal ? '<span class="chip">🎯 今日の目標 達成</span>' : `<span class="chip">🎯 あと${S.goal - S.daily.xp}XP</span>`}</div>
    <div style="height:90px"></div></div></div><div class="chk"><button class="btn" id="done">つづける</button></div>`;
  let n = 0; const target = L.xp, el = $('#cxp'), step = Math.max(1, Math.round(target / 30));
  const iv = setInterval(() => { n = Math.min(target, n + step); el.textContent = n; if (n >= target || !el.isConnected) clearInterval(iv); }, 25);
  if (lucky) setTimeout(() => { if (!$('#luck')) return; $('#luck').innerHTML = `<div class="lucky"><small>🎰 ラッキーボーナス！</small>XP ×${lucky}</div>`; sfx.big(); confetti(100, 0.5); }, 900);
  await new Promise((r) => { $('#done').onclick = r; });

  const evs = [];
  if (lv1 > L.lv0) evs.push({ em: '🆙', title: `レベル ${lv1}！`, text: `称号：「${titleOf(lv1)}」`, big: true });
  if (firstToday && st >= 3 && [3, 7, 14, 30, 50, 100].includes(st)) evs.push({ em: '🔥', title: `${st}日連続！`, text: frz ? 'ごほうびにストリークフリーズ🧊を1つゲット！' : 'この調子で続けよう！', big: true });
  quests.forEach((q) => evs.push({ em: '📜', title: 'クエスト達成！', text: `${q.t}<br>🪙 +${q.r}` }));
  badges.forEach((b) => evs.push({ em: b.em, title: `バッジ獲得：${b.name}`, text: b.desc, big: true }));
  if (goalNow) evs.push({ em: '🎯', title: '今日の目標を達成！', text: '宝箱が開けられるようになりました🎁', big: true });
  lesson.hidden = true; lesson.innerHTML = ''; document.body.style.overflow = ''; L = null;
  tab = 'home'; render();
  for (const e of evs) { e.big ? (sfx.big(), confetti(140)) : sfx.coin(); await modal({ em: e.em, title: e.title, text: e.text }); }
  if (goalNow) { await wait(200); await openChest(); }
  render();
}

async function openChest() {
  rollDay();
  if (S.daily.xp < S.goal || S.daily.chest) return;
  await new Promise((res) => {
    const m = $('#modal'); m.hidden = false;
    m.innerHTML = '<div class="mbox"><h2>今日の宝箱</h2><p>タップして開けよう！</p><span class="chest" id="ch">🎁</span></div>';
    $('#ch').onclick = () => { sfx.coin(); res(); };
  });
  S.daily.chest = true; S.stats.chests++;
  const r = Math.random(); let em, title, text, rare = false;
  if (r < 0.5) { const c = 20 + rnd(31); S.coins += c; em = '🪙'; title = `${c}ルピアゲット！`; text = 'コインが貯まったよ'; }
  else if (r < 0.75) { addXP(30); em = '⭐'; title = '+30 XP！'; text = 'ボーナスXPをゲット'; }
  else if (r < 0.9) { if (S.freezes < 3) { S.freezes++; em = '🧊'; title = 'ストリークフリーズ！'; text = '1日休んでも連続記録を守れます'; } else { S.coins += 40; em = '🪙'; title = '40ルピアゲット！'; text = 'コインが貯まったよ'; } }
  else { S.coins += 150; em = '💎'; title = '大当たり！150ルピア！'; text = 'レアなごほうび！'; rare = true; }
  const bs = checkBadges(); save();
  rare ? (sfx.big(), confetti(260)) : (sfx.win(), confetti(120));
  await modal({ em, title, text, rare });
  for (const b of bs) { sfx.big(); confetti(100); await modal({ em: b.em, title: `バッジ獲得：${b.name}`, text: b.desc }); }
}

async function quit() {
  if (!L) return;
  if (L.i > 0 && !(await confirmModal('ここでやめますか？獲得したXPは残ります。', 'やめる', 'つづける'))) return;
  if (!L) return;
  try { speechSynthesis.cancel(); } catch (e) { /* noop */ }
  lesson.hidden = true; lesson.innerHTML = ''; document.body.style.overflow = ''; L = null; save(); render();
}

/* ---------- actions ---------- */
const acts = {
  tab: (d) => { tab = d.tab; render(); window.scrollTo(0, 0); },
  unit: (d) => { const u = UNITS.find((x) => x.id === d.u); startSession('unit', u); },
  review: () => {
    if (!ALL.some((i) => S.words[i.id] && S.words[i.id].seen)) return toast('まずはレッスンを1つやってみよう！');
    startSession('review', null);
  },
  copyurl: () => {
    const done = () => toast('URLをコピーしました。Chromeに貼り付けて開いてください');
    const fb = () => { const t = document.createElement('textarea'); t.value = OPEN_URL; document.body.appendChild(t); t.select(); try { document.execCommand('copy'); done(); } catch (e) { toast(OPEN_URL); } t.remove(); };
    try { navigator.clipboard.writeText(OPEN_URL).then(done, fb); } catch (e) { fb(); }
  },
  hidehint: () => { hintHidden = true; try { sessionStorage.setItem('belajar-hint', '1'); } catch (e) { /* noop */ } render(); },
  say: (d) => speak(d.t),
  slow: (d) => speak(d.t, 0.55),
  quit,
  chest: () => openChest().then(render),
  goal: (d) => { S.goal = +d.g; save(); render(); },
  sound: () => { S.sound = !S.sound; save(); render(); },
  freeze: () => {
    if (S.freezes >= 3) return toast('フリーズは最大3個までです');
    if (S.coins < 50) return toast('コインが足りません（50必要）');
    S.coins -= 50; S.freezes++; save(); sfx.coin(); render(); toast('🧊 ストリークフリーズを手に入れた！');
  },
  reset: async () => { if (await confirmModal('学習データをすべて消します。よろしいですか？', '消す')) { S = fresh(); save(); tab = 'home'; render(); } },
};
document.addEventListener('click', (e) => {
  const t = e.target.closest('[data-act]');
  if (t && acts[t.dataset.act]) acts[t.dataset.act](t.dataset, t);
});

/* ---------- boot ---------- */
render();
const chk = checkBadges(); if (chk.length) save();
if ('serviceWorker' in navigator && location.protocol.startsWith('http')) navigator.serviceWorker.register('sw.js').catch(() => {});
window.__belajar = { get S() { return S; }, ALL, UNITS }; // デバッグ・テスト用
})();
