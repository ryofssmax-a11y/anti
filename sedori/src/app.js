/* global Calc */
"use strict";

// デスクトップ版（Electron）は window.api がある。スマホ・ブラウザ版（PWA）は localStorage に保存する
const IS_DESKTOP = !!window.api;
const api = window.api || {
  load: async () => JSON.parse(localStorage.getItem("sedori") || "null"),
  save: async d => localStorage.setItem("sedori", JSON.stringify(d)),
  openExternal: async url => window.open(url, "_blank", "noopener"),
  saveFile: async ({ name, content, ext }) => {
    const type = ext === "json" ? "application/json" : "text/csv";
    const file = new File([content], name, { type });
    // スマホでは共有シート（ファイルに保存・Google ドライブ・メール等）を使う
    if (navigator.canShare && navigator.canShare({ files: [file] }) && matchMedia("(pointer: coarse)").matches) {
      try { await navigator.share({ files: [file], title: name }); return name; } catch (e) { if (e.name === "AbortError") return null; }
    }
    const a = document.createElement("a");
    a.href = URL.createObjectURL(file);
    a.download = name; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 10000);
    return name;
  },
  openJson: () => new Promise((resolve, reject) => {
    const input = document.createElement("input");
    input.type = "file"; input.accept = "application/json,.json";
    input.onchange = async () => {
      try { resolve(input.files[0] ? JSON.parse(await input.files[0].text()) : null); } catch { reject(new Error("ファイルを読み込めませんでした")); }
    };
    input.click();
  }),
  fetchRate: async () => {
    const res = await fetch("https://open.er-api.com/v6/latest/USD");
    if (!res.ok) throw new Error("為替レートの取得に失敗しました (" + res.status + ")");
    const j = await res.json();
    if (!j.rates || !j.rates.JPY) throw new Error("為替レートの形式が想定外です");
    return { rate: j.rates.JPY, updated: j.time_last_update_utc };
  },
  ebaySearch: async () => { throw new Error("eBay 相場の自動取得はPC版のみです。「eBay 売却済み」ボタンで相場を確認してください"); },
};

const SOURCES = ["ヤフオク", "メルカリ", "ラクマ", "Yahoo!フリマ", "駿河屋", "ハードオフ", "セカンドストリート", "Amazon", "店舗", "その他"];
const STATUS = { stock: "未出品", listed: "出品中", sold: "売却済(未発送)", shipped: "発送済", cancelled: "キャンセル・返品" };
const EXPENSE_CATS = ["eBayストア月額", "梱包資材", "国内送料", "ツール・サブスク", "交通費", "通信費", "その他"];
const SEARCH_SITES = [
  ["eBay 売却済み", k => `https://www.ebay.com/sch/i.html?_nkw=${k}&LH_Sold=1&LH_Complete=1`],
  ["eBay 出品中", k => `https://www.ebay.com/sch/i.html?_nkw=${k}`],
  ["ヤフオク", k => `https://auctions.yahoo.co.jp/search/search?p=${k}`],
  ["ヤフオク落札相場", k => `https://auctions.yahoo.co.jp/closedsearch/closedsearch?p=${k}`],
  ["メルカリ", k => `https://jp.mercari.com/search?keyword=${k}&status=on_sale`],
  ["ラクマ", k => `https://fril.jp/s?query=${k}`],
  ["Yahoo!フリマ", k => `https://paypayfleamarket.yahoo.co.jp/search/${k}`],
  ["駿河屋", k => `https://www.suruga-ya.jp/search?search_word=${k}`],
  ["ハードオフ", k => `https://netmall.hardoff.co.jp/search/?q=${k}`],
  ["セカスト", k => `https://www.2ndstreet.jp/search?keyword=${k}`],
];
// 「全サイトで探す」で開く仕入れ先
const BUY_SITES = ["ヤフオク", "メルカリ", "ラクマ", "Yahoo!フリマ", "駿河屋", "ハードオフ", "セカスト"];

let state = { settings: { ...Calc.DEFAULT_SETTINGS }, candidates: [], watches: [], items: [], expenses: [], rateUpdated: "" };
let ui = { tab: "dashboard", invFilter: "active", invSearch: "", onlyGood: false, year: new Date().getFullYear(), month: "", expMonth: "", research: null };

// ---------- ユーティリティ ----------
const $ = (s, el = document) => el.querySelector(s);
const esc = v => String(v === null || v === undefined ? "" : v).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const n = v => (v === "" || v === null || v === undefined || !Number.isFinite(+v) ? 0 : +v);
const yen = v => (n(v) < 0 ? "-¥" : "¥") + Math.abs(Math.round(n(v))).toLocaleString("ja-JP");
const usd = v => "$" + n(v).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const pct = v => n(v).toFixed(1) + "%";
const sign = v => (n(v) > 0 ? "pos" : n(v) < 0 ? "neg" : "");
const pad = x => String(x).padStart(2, "0");
const dstr = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const today = () => dstr(new Date());
const thisMonth = () => today().slice(0, 7);
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
const daysBetween = (a, b) => Math.floor((new Date(b) - new Date(a)) / 86400000);
const S = () => state.settings;
const errMsg = e => String((e && e.message) || e).replace(/^Error invoking remote method '[^']+': (Error: )?/, "");
const JUDGE = { good: ["good", "◎ 仕入れ候補"], ok: ["ok", "△ 薄利"], bad: ["bad", "✕ 赤字"] };
const judgeBadge = r => { const [c, t] = JUDGE[Calc.judge(r, S())]; return `<span class="badge ${c}">${t}</span>`; };

function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => t.classList.remove("show"), 2600);
}

function save() {
  api.save(state).catch(e => toast("保存に失敗しました: " + errMsg(e)));
}

function nextSku() {
  const prefix = "S" + today().slice(2).replace(/-/g, "") + "-";
  const used = state.items.filter(i => (i.sku || "").startsWith(prefix)).map(i => +i.sku.slice(prefix.length) || 0);
  return prefix + pad(Math.max(0, ...used) + 1);
}

// フォーム部品
function fld(name, label, value, opt = {}) {
  const cls = opt.wide ? ' class="wide"' : "";
  const attrs = `name="${name}" ${opt.required ? "required" : ""} ${opt.placeholder ? `placeholder="${esc(opt.placeholder)}"` : ""}`;
  if (opt.options) {
    const opts = opt.options.map(o => {
      const [v, t] = Array.isArray(o) ? o : [o, o];
      return `<option value="${esc(v)}" ${String(v) === String(value) ? "selected" : ""}>${esc(t)}</option>`;
    }).join("");
    return `<label${cls}>${label}<select ${attrs}>${opts}</select></label>`;
  }
  if (opt.type === "textarea") return `<label${cls}>${label}<textarea ${attrs}>${esc(value)}</textarea></label>`;
  if (opt.type === "checkbox") return `<label${cls} style="flex-direction:row;align-items:center;gap:6px"><input type="checkbox" name="${name}" ${value ? "checked" : ""}>${label}</label>`;
  const type = opt.type || "text";
  const step = type === "number" ? `step="${opt.step || "any"}"` : "";
  return `<label${cls}>${label}<input type="${type}" ${step} ${attrs} value="${esc(value)}"></label>`;
}

function formData(form) {
  const o = {};
  for (const el of form.elements) {
    if (!el.name) continue;
    if (el.type === "checkbox") o[el.name] = el.checked;
    else if (el.type === "number") o[el.name] = el.value === "" ? "" : +el.value;
    else o[el.name] = el.value.trim();
  }
  return o;
}

function profitPreview(r, extra = "") {
  return `<div class="preview">
    <div>売上（円）<b>${yen(r.salesJpy)}</b></div>
    <div>eBay手数料<b>${yen(r.feesJpy)}</b></div>
    <div>入金コスト<b>${yen(r.payoutFeeJpy)}</b></div>
    <div>仕入れ総額<b>${yen(r.purchaseTotal)}</b></div>
    <div>国際送料<b>${yen(r.intlShipping)}</b></div>
    <div>利益<b class="${sign(r.profit)}">${yen(r.profit)}</b></div>
    <div>利益率 / ROI<b>${pct(r.margin)} / ${pct(r.roi)}</b></div>
    <div>判定<b>${judgeBadge(r)}</b></div>${extra}
  </div>`;
}

// ---------- ダイアログ ----------
let dlgHandler = null;
function openDialog(title, body, onSave, onInput, saveLabel = "保存") {
  const form = $("#dlgForm");
  const buttons = onSave
    ? `<button class="b" value="cancel" formnovalidate>キャンセル</button><button class="b primary" value="save">${saveLabel}</button>`
    : `<button class="b primary" value="cancel" formnovalidate>${saveLabel}</button>`;
  // 見出しにフォーカスして、スマホでキーボードがいきなり開かないようにする
  form.innerHTML = `<h3 tabindex="-1" autofocus>${title}</h3>${body}<div class="foot">${buttons}</div>`;
  dlgHandler = onSave;
  form.oninput = onInput ? () => onInput(form) : null;
  if (onInput) onInput(form);
  $("#dlg").showModal();
}
$("#dlgForm").addEventListener("submit", e => {
  e.preventDefault();
  const btn = e.submitter;
  if (btn && btn.value === "save" && dlgHandler) {
    if (dlgHandler(formData(e.target)) === false) return;
  }
  $("#dlg").close();
});

// ---------- グラフ（単一系列の棒グラフ。負の値は基準線の下へ） ----------
function barChart(points, valueLabel) {
  // 画面幅に合わせて描くと、スマホでも文字が小さくなりすぎない
  const W = Math.max(340, Math.min(760, ($("#view").clientWidth || 760) - 40)), H = W < 500 ? 200 : 230, L = 52, R = 8, T = 12, B = 28;
  const vals = points.map(p => p.value);
  let max = Math.max(0, ...vals), min = Math.min(0, ...vals);
  if (max === min) max = 1;
  // 目盛りは 1・2・5 系のきりの良い間隔にする
  const raw = (max - min) / 4, mag = Math.pow(10, Math.floor(Math.log10(raw)));
  const step = [1, 2, 2.5, 5, 10].map(f => f * mag).find(v => v >= raw);
  max = Math.ceil(max / step) * step; min = Math.floor(min / step) * step;
  const y = v => T + (max - v) / (max - min) * (H - T - B);
  const slot = (W - L - R) / points.length, bw = Math.min(36, slot * 0.6);
  const ticks = [];
  for (let v = min; v <= max + step / 2; v += step) ticks.push(v);
  let svg = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(valueLabel)}">`;
  for (const t of ticks) svg += `<line class="gl" x1="${L}" x2="${W - R}" y1="${y(t)}" y2="${y(t)}"/><text class="ax" x="${L - 6}" y="${y(t) + 4}" text-anchor="end">${t >= 10000 || t <= -10000 ? (t / 10000).toFixed(t % 10000 ? 1 : 0) + "万" : Math.round(t).toLocaleString()}</text>`;
  points.forEach((p, i) => {
    const cx = L + slot * i + slot / 2, y0 = y(0), y1 = y(p.value);
    const top = Math.min(y0, y1), h = Math.max(Math.abs(y1 - y0), p.value ? 1 : 0), r = Math.min(4, h, bw / 2);
    // 基準線側は角を付けず、値の側だけ角丸にする
    const d = p.value >= 0
      ? `M${cx - bw / 2},${y0}V${top + r}Q${cx - bw / 2},${top} ${cx - bw / 2 + r},${top}H${cx + bw / 2 - r}Q${cx + bw / 2},${top} ${cx + bw / 2},${top + r}V${y0}Z`
      : `M${cx - bw / 2},${y0}V${y1 - r}Q${cx - bw / 2},${y1} ${cx - bw / 2 + r},${y1}H${cx + bw / 2 - r}Q${cx + bw / 2},${y1} ${cx + bw / 2},${y1 - r}V${y0}Z`;
    svg += `<g data-tip="${esc(p.label + "　" + valueLabel + " " + yen(p.value) + (p.extra ? "　" + p.extra : ""))}">
      <rect class="hit" x="${cx - slot / 2}" y="${T}" width="${slot}" height="${H - T - B}"/>
      ${h ? `<path class="bar ${p.value < 0 ? "neg" : ""}" d="${d}"/>` : ""}
      ${W >= 500 || i % 2 === points.length % 2 ? `<text class="ax" x="${cx}" y="${H - 8}" text-anchor="middle">${esc(p.short || p.label)}</text>` : ""}</g>`;
  });
  svg += `<line class="base" x1="${L}" x2="${W - R}" y1="${y(0)}" y2="${y(0)}"/></svg>`;
  return `<div class="chart">${svg}</div>`;
}
document.addEventListener("mousemove", e => {
  const g = e.target.closest && e.target.closest("[data-tip]");
  const tip = $("#tip");
  if (!g) { tip.hidden = true; return; }
  tip.textContent = g.dataset.tip;
  tip.hidden = false;
  tip.style.left = Math.min(e.clientX + 14, innerWidth - tip.offsetWidth - 8) + "px";
  tip.style.top = (e.clientY + 14) + "px";
});

// ---------- 画面 ----------
const views = {};

views.dashboard = () => {
  const t = today(), m = thisMonth();
  const s = S();
  const sold = state.items.filter(Calc.isSold);
  const todays = sold.filter(i => i.soldDate === t).map(i => Calc.itemFigures(i, s));
  const sum = (arr, k) => arr.reduce((a, x) => a + x[k], 0);
  const mon = Calc.monthlySummary(state.items, state.expenses, s, [m]).find(x => x.month === m);
  const inv = Calc.inventoryValue(state.items);
  const unshipped = state.items.filter(i => i.status === "sold");
  const old = state.items.filter(i => (i.status === "stock" || i.status === "listed") && i.purchaseDate && daysBetween(i.purchaseDate, t) >= 90);
  const goal = n(s.monthlyGoal), prog = goal > 0 ? Math.max(0, Math.min(100, mon.netProfit / goal * 100)) : 0;
  const top = state.candidates.map(c => ({ c, r: candResult(c) })).filter(x => Calc.judge(x.r, s) === "good").sort((a, b) => b.r.profit - a.r.profit).slice(0, 5);
  const months = lastMonths(12);
  const summ = Calc.monthlySummary(state.items, state.expenses, s, months).filter(x => months.includes(x.month));

  return `<h1>ダッシュボード <span class="muted" style="font-size:.85rem;font-weight:400">${t}</span></h1>
  <div class="grid kpis">
    <div class="kpi"><div class="l">今日の販売</div><div class="v">${todays.length}件</div><div class="s">売上 ${yen(sum(todays, "salesJpy"))} ／ 利益 <span class="${sign(sum(todays, "profit"))}">${yen(sum(todays, "profit"))}</span></div></div>
    <div class="kpi"><div class="l">今月の売上（${mon.soldCount}件）</div><div class="v">${yen(mon.sales)}</div><div class="s">利益率 ${pct(mon.margin)}</div></div>
    <div class="kpi"><div class="l">今月の純利益（経費差引後）</div><div class="v ${sign(mon.netProfit)}">${yen(mon.netProfit)}</div><div class="s">目標 ${yen(goal)}（${pct(prog)}）</div><div class="progress"><i style="width:${prog}%"></i></div></div>
    <div class="kpi"><div class="l">在庫</div><div class="v">${inv.count}点</div><div class="s">仕入れ額 ${yen(inv.amount)}</div></div>
    <div class="kpi"><div class="l">未発送の注文</div><div class="v ${unshipped.length ? "neg" : ""}">${unshipped.length}件</div><div class="s">${unshipped.length ? "発送をお忘れなく" : "すべて発送済み"}</div></div>
  </div>
  <div class="card"><h2>月別の純利益（直近12か月）</h2>${barChart(summ.map(x => ({ label: x.month, short: +x.month.slice(5) + "月", value: x.netProfit, extra: `売上 ${yen(x.sales)}・${x.soldCount}件` })), "純利益")}</div>
  <div class="grid two">
    <div class="card"><h2>未発送の注文</h2>${unshipped.length ? `<table><tr><th>SKU</th><th>商品名</th><th>売却日</th><th></th></tr>${unshipped.map(i => `<tr><td>${esc(i.sku)}</td><td class="t">${esc(i.title)}</td><td>${esc(i.soldDate)}</td><td><button class="b sm" data-act="ship" data-id="${i.id}">発送済にする</button></td></tr>`).join("")}</table>` : `<div class="empty">未発送の注文はありません</div>`}</div>
    <div class="card"><h2>利益候補トップ5</h2>${top.length ? `<table><tr><th>商品名</th><th class="n">仕入れ</th><th class="n">利益</th><th class="n">利益率</th></tr>${top.map(x => `<tr><td class="t">${esc(x.c.title)}</td><td class="n">${yen(x.c.purchasePrice)}</td><td class="n pos">${yen(x.r.profit)}</td><td class="n">${pct(x.r.margin)}</td></tr>`).join("")}</table>` : `<div class="empty">「リサーチ・利益計算」で候補を登録すると表示されます</div>`}</div>
    <div class="card"><h2>長期在庫（仕入れから90日以上）</h2>${old.length ? `<table><tr><th>SKU</th><th>商品名</th><th class="n">日数</th><th class="n">仕入れ額</th></tr>${old.sort((a, b) => a.purchaseDate.localeCompare(b.purchaseDate)).slice(0, 10).map(i => `<tr><td>${esc(i.sku)}</td><td class="t">${esc(i.title)}</td><td class="n">${daysBetween(i.purchaseDate, t)}日</td><td class="n">${yen(i.purchasePrice)}</td></tr>`).join("")}</table>` : `<div class="empty">長期在庫はありません</div>`}</div>
  </div>`;
};

function lastMonths(count) {
  const d = new Date(); d.setDate(1);
  const out = [];
  for (let i = count - 1; i >= 0; i--) {
    const x = new Date(d.getFullYear(), d.getMonth() - i, 1);
    out.push(`${x.getFullYear()}-${pad(x.getMonth() + 1)}`);
  }
  return out;
}

// ----- リサーチ -----
function candResult(c) {
  return Calc.calcProfit({ sellUsd: c.ebayPriceUsd, shipChargeUsd: c.ebayShippingUsd, purchase: c.purchasePrice, purchaseShipping: c.purchaseShipping, intlShipping: c.intlShippingJpy }, S());
}

views.research = () => {
  const s = S(), rs = ui.research;
  let apiBlock = "";
  if (rs && rs.result) {
    const prices = rs.result.items.map(i => i.price + i.shipping);
    const med = Calc.median(prices);
    const avg = prices.length ? prices.reduce((a, b) => a + b, 0) / prices.length : 0;
    const max = Calc.maxPurchase(med, 0, s.defaultIntlShipping, s);
    apiBlock = `<div class="preview">
      <div>出品数<b>${rs.result.total.toLocaleString()}件</b></div>
      <div>最安（送料込）<b>${usd(Math.min(...prices) || 0)}</b></div>
      <div>中央値（送料込）<b>${usd(med)}</b></div>
      <div>平均<b>${usd(avg)}</b></div>
      <div>最高<b>${usd(Math.max(...prices) || 0)}</b></div>
      <div>仕入れ上限の目安<b class="pos">${yen(max)}</b></div>
    </div>
    <p class="note">※ Browse API は「出品中」の価格です。実際に売れた価格は「eBay 売却済み」で必ず確認してください。仕入れ上限は中央値で売れ、国際送料 ${yen(s.defaultIntlShipping)} の場合に最低利益 ${yen(s.minProfit)}・利益率 ${s.minMargin}% を確保できる仕入れ総額です。</p>
    <div class="row" style="margin-top:8px"><button class="b" data-act="watch-from-research">ウォッチリストに追加</button><button class="b" data-act="cand-from-research">この相場で候補を登録</button></div>
    <div class="tbl-wrap" style="max-height:320px;margin-top:10px"><table><tr><th></th><th>商品名</th><th>状態</th><th>発送元</th><th class="n">価格</th><th class="n">送料</th></tr>
    ${rs.result.items.slice(0, 50).map(i => `<tr><td>${i.image ? `<img class="thumb" src="${esc(i.image)}" alt="">` : ""}</td><td class="t"><a href="${esc(i.url)}" target="_blank">${esc(i.title)}</a></td><td>${esc(i.condition)}</td><td>${esc(i.location || "")}</td><td class="n">${usd(i.price)}</td><td class="n">${usd(i.shipping)}</td></tr>`).join("")}</table></div>`;
  } else if (rs && rs.loading) apiBlock = `<p class="muted">eBay から取得中…</p>`;

  const list = state.candidates.map(c => ({ c, r: candResult(c) }))
    .filter(x => !ui.onlyGood || Calc.judge(x.r, s) === "good")
    .sort((a, b) => b.r.profit - a.r.profit);

  return `<h1>リサーチ・利益計算</h1>
  <div class="card">
    <h2>貼り付けで取り込み</h2>
    <p class="note" style="margin:0 0 10px">メルカリ・ヤフオクなどで「共有 → コピー」した文章や、商品ページのURL・商品名・価格を貼り付けると、下の利益シミュレーターに自動で入力します。</p>
    <div class="row"><button class="b primary" data-act="paste-clip">コピーした内容を貼り付け</button></div>
    <textarea id="pasteBox" style="width:100%;margin-top:10px" placeholder="うまく貼り付けできないときは、ここを長押し（右クリック）して貼り付け"></textarea>
    <div class="row" style="margin-top:6px"><button class="b" data-act="paste-parse">読み取る</button><span id="pasteResult" class="muted" style="font-size:.85rem"></span></div>
  </div>

  <div class="card">
    <h2>相場リサーチ</h2>
    <div class="row">
      <input id="kw" style="flex:1;min-width:240px" placeholder="キーワード（英語推奨：例 Nikon F3 body）" value="${esc(rs ? rs.keyword : "")}">
      <select id="cond"><option value="">状態：すべて</option><option value="used" ${rs && rs.condition === "used" ? "selected" : ""}>中古</option><option value="new" ${rs && rs.condition === "new" ? "selected" : ""}>新品</option></select>
      ${IS_DESKTOP ? `<button class="b primary" data-act="ebay-api">eBay 相場を取得</button>` : ""}
    </div>
    <div class="row links" style="margin-top:10px">${SEARCH_SITES.map(([name], i) => `<button class="b" data-act="site" data-i="${i}">${name}</button>`).join("")}</div>
    ${apiBlock}
  </div>

  <div class="card">
    <h2>利益シミュレーター（候補に登録）</h2>
    <form id="candForm" class="form">
      ${candFields({})}
      <div class="row" style="align-items:flex-end"><button class="b primary" type="submit">候補リストに追加</button></div>
    </form>
    <div id="candPreview"></div>
  </div>

  <div class="card">
    <div class="row" style="justify-content:space-between;margin-bottom:8px">
      <h2 style="margin:0">仕入れ候補リスト（${state.candidates.length}件）</h2>
      <label class="row" style="gap:6px"><input type="checkbox" id="onlyGood" ${ui.onlyGood ? "checked" : ""}> 利益候補（◎）のみ表示</label>
    </div>
    ${list.length ? `<div class="tbl-wrap"><table class="stack">
      <tr><th>判定</th><th>商品名</th><th>仕入れ先</th><th class="n">仕入れ総額</th><th class="n">eBay価格</th><th class="n">手数料等</th><th class="n">国際送料</th><th class="n">利益</th><th class="n">利益率</th><th class="n">ROI</th><th></th></tr>
      ${list.map(({ c, r }) => `<tr>
        <td>${judgeBadge(r)}</td>
        <td class="t" title="${esc(c.title)}">${c.sourceUrl ? `<a href="${esc(c.sourceUrl)}" target="_blank">${esc(c.title)}</a>` : esc(c.title)}</td>
        <td>${esc(c.source)}</td><td class="n">${yen(r.purchaseTotal)}</td><td class="n">${usd(r.salesUsd)}</td>
        <td class="n">${yen(r.feesJpy + r.payoutFeeJpy)}</td><td class="n">${yen(r.intlShipping)}</td>
        <td class="n ${sign(r.profit)}"><b>${yen(r.profit)}</b></td><td class="n">${pct(r.margin)}</td><td class="n">${pct(r.roi)}</td>
        <td><div class="row" style="flex-wrap:nowrap"><button class="b sm primary" data-act="cand-buy" data-id="${c.id}">仕入れた</button><button class="b sm" data-act="cand-edit" data-id="${c.id}">編集</button><button class="b sm danger" data-act="cand-del" data-id="${c.id}">削除</button></div></td>
      </tr>`).join("")}</table></div>` : `<div class="empty">候補はまだありません。上のフォームで仕入れ値と eBay 販売予想価格を入力してください。</div>`}
  </div>`;
};

function candFields(c) {
  return `${fld("title", "商品名", c.title || "", { required: true, wide: true })}
    ${fld("source", "仕入れ先", c.source || "メルカリ", { options: SOURCES })}
    ${fld("sourceUrl", "仕入れ先URL", c.sourceUrl || "", { placeholder: "https://" })}
    ${fld("purchasePrice", "仕入れ価格（円）", c.purchasePrice ?? "", { type: "number", required: true })}
    ${fld("purchaseShipping", "国内送料・手数料（円）", c.purchaseShipping ?? 0, { type: "number" })}
    ${fld("ebayPriceUsd", "eBay 販売予想価格（USD）", c.ebayPriceUsd ?? "", { type: "number", required: true })}
    ${fld("ebayShippingUsd", "購入者負担送料（USD）", c.ebayShippingUsd ?? 0, { type: "number" })}
    ${fld("intlShippingJpy", "国際送料（円）", c.intlShippingJpy ?? S().defaultIntlShipping, { type: "number" })}`;
}

function candPreview(form, target) {
  const d = formData(form);
  if (!n(d.ebayPriceUsd)) { target.innerHTML = `<p class="note">eBay 販売予想価格を入力すると、利益と仕入れ上限価格を計算します。</p>`; return; }
  const r = candResult(d);
  const max = Calc.maxPurchase(n(d.ebayPriceUsd), n(d.ebayShippingUsd), n(d.intlShippingJpy), S());
  target.innerHTML = profitPreview(r, `<div>仕入れ上限（送料込）<b>${yen(max)}</b></div>`);
}

// ----- ウォッチリスト -----
views.watch = () => {
  const s = S();
  return `<h1>ウォッチリスト</h1>
  <div class="card">
    <h2>キーワードを追加</h2>
    <form id="watchForm" class="form">
      ${fld("keyword", "キーワード", "", { required: true, wide: true, placeholder: "例 Canon AE-1 Program" })}
      ${fld("condition", "状態", "", { options: [["", "すべて"], ["used", "中古"], ["new", "新品"]] })}
      ${fld("sellUsd", "想定販売価格（USD・任意）", "", { type: "number", placeholder: "相場取得で自動入力" })}
      ${fld("intlShippingJpy", "国際送料（円）", s.defaultIntlShipping, { type: "number" })}
      <div class="row" style="align-items:flex-end"><button class="b primary" type="submit">追加</button></div>
    </form>
    <p class="note">eBay の相場から「この金額以下で仕入れれば利益が出る」上限価格を計算します。上限価格を見ながら「全サイトで探す」でヤフオク・メルカリ等を一括検索してください。</p>
  </div>
  <div class="card">
    <div class="row" style="justify-content:space-between;margin-bottom:8px"><h2 style="margin:0">ウォッチ中（${state.watches.length}件）</h2>${IS_DESKTOP ? `<button class="b" data-act="watch-refresh-all" ${state.watches.length ? "" : "disabled"}>すべての相場を更新</button>` : ""}</div>
    ${state.watches.length ? `<div class="tbl-wrap"><table class="stack">
      <tr><th>キーワード</th><th>状態</th><th class="n">出品数</th><th class="n">最安</th><th class="n">中央値</th><th class="n">想定販売価格</th><th class="n">国際送料</th><th class="n">仕入れ上限</th><th>更新</th><th></th></tr>
      ${state.watches.map(w => {
        const st = w.stats || {};
        const max = n(w.sellUsd) ? Calc.maxPurchase(n(w.sellUsd), 0, n(w.intlShippingJpy), s) : null;
        return `<tr>
          <td>${esc(w.keyword)}</td><td>${{ used: "中古", new: "新品" }[w.condition] || "すべて"}</td>
          <td class="n">${st.total !== undefined ? st.total.toLocaleString() : "-"}</td><td class="n">${st.min !== undefined ? usd(st.min) : "-"}</td><td class="n">${st.median !== undefined ? usd(st.median) : "-"}</td>
          <td class="n"><input type="number" step="any" style="width:90px;text-align:right" data-watch-sell="${w.id}" value="${esc(w.sellUsd)}"></td>
          <td class="n">${yen(w.intlShippingJpy)}</td>
          <td class="n">${max === null ? "-" : `<b class="pos">${yen(max)}</b>`}</td>
          <td class="muted">${esc(st.fetchedAt || "")}</td>
          <td><div class="row" style="flex-wrap:nowrap"><button class="b sm primary" data-act="watch-open" data-id="${w.id}">全サイトで探す</button>${IS_DESKTOP ? `<button class="b sm" data-act="watch-refresh" data-id="${w.id}">相場更新</button>` : ""}<button class="b sm danger" data-act="watch-del" data-id="${w.id}">削除</button></div></td>
        </tr>`;
      }).join("")}</table></div>` : `<div class="empty">ウォッチ中のキーワードはありません</div>`}
  </div>`;
};

async function refreshWatch(w) {
  const s = S();
  const res = await api.ebaySearch({ keyword: w.keyword, condition: w.condition, clientId: s.ebayClientId, clientSecret: s.ebayClientSecret });
  const prices = res.items.map(i => i.price + i.shipping);
  w.stats = { total: res.total, min: prices.length ? Math.min(...prices) : 0, median: Calc.median(prices), fetchedAt: today() };
  if (prices.length) w.sellUsd = Math.round(w.stats.median * 100) / 100;
}

// ----- 在庫・販売 -----
const INV_FILTERS = [["active", "在庫（未出品・出品中）"], ["stock", "未出品"], ["listed", "出品中"], ["sold", "未発送"], ["shipped", "発送済"], ["cancelled", "キャンセル"], ["all", "すべて"]];

views.inventory = () => {
  const s = S(), t = today();
  const match = i => ui.invFilter === "all" || (ui.invFilter === "active" ? (i.status === "stock" || i.status === "listed") : i.status === ui.invFilter);
  const q = ui.invSearch.toLowerCase();
  const list = state.items.filter(match).filter(i => !q || (i.title + " " + i.sku + " " + (i.memo || "")).toLowerCase().includes(q))
    .sort((a, b) => (b.soldDate || b.purchaseDate || "").localeCompare(a.soldDate || a.purchaseDate || ""));
  const count = f => state.items.filter(i => f === "all" || (f === "active" ? (i.status === "stock" || i.status === "listed") : i.status === f)).length;
  return `<h1>在庫・販売管理</h1>
  <div class="row" style="margin-bottom:12px"><button class="b primary" data-act="item-new">＋ 仕入れを登録</button><input id="invSearch" placeholder="商品名・SKU・メモで検索" value="${esc(ui.invSearch)}" style="min-width:240px"><button class="b" data-act="export-items" style="margin-left:auto">CSV出力</button></div>
  <div class="tabs">${INV_FILTERS.map(([k, l]) => `<button class="b sm ${ui.invFilter === k ? "on" : ""}" data-act="inv-filter" data-f="${k}">${l}（${count(k)}）</button>`).join("")}</div>
  <div class="card" style="padding:8px 10px">${list.length ? `<div class="tbl-wrap"><table class="stack">
    <tr><th>SKU</th><th>商品名</th><th>状態</th><th>仕入日</th><th class="n">仕入れ総額</th><th class="n">出品/売価</th><th>売却日</th><th class="n">利益</th><th class="n">日数</th><th></th></tr>
    ${list.map(i => {
      const sold = Calc.isSold(i);
      const r = sold ? Calc.itemFigures(i, s) : Calc.calcProfit({ sellUsd: i.listPriceUsd, purchase: i.purchasePrice, purchaseShipping: i.purchaseShipping, otherCost: i.otherCost, intlShipping: i.intlShippingJpy || s.defaultIntlShipping }, s);
      const days = i.purchaseDate ? daysBetween(i.purchaseDate, i.soldDate || t) : "";
      return `<tr>
        <td>${esc(i.sku)}</td>
        <td class="t" title="${esc(i.title)}">${i.ebayUrl ? `<a href="${esc(i.ebayUrl)}" target="_blank">${esc(i.title)}</a>` : esc(i.title)}</td>
        <td><select data-status="${i.id}">${Object.entries(STATUS).map(([k, l]) => `<option value="${k}" ${i.status === k ? "selected" : ""}>${l}</option>`).join("")}</select></td>
        <td>${esc(i.purchaseDate)}</td>
        <td class="n">${yen(n(i.purchasePrice) + n(i.purchaseShipping) + n(i.otherCost))}</td>
        <td class="n">${sold ? usd(n(i.soldPriceUsd) + n(i.shippingChargedUsd)) : i.listPriceUsd ? `<span class="muted">${usd(i.listPriceUsd)}</span>` : "-"}</td>
        <td>${esc(i.soldDate || "")}</td>
        <td class="n">${sold || i.listPriceUsd ? `<span class="${sign(r.profit)}">${sold ? "" : "見込 "}${yen(r.profit)}</span>` : "-"}</td>
        <td class="n">${days === "" ? "" : days + "日"}</td>
        <td><div class="row" style="flex-wrap:nowrap">${sold ? "" : `<button class="b sm primary" data-act="item-sold" data-id="${i.id}">売れた</button>`}<button class="b sm" data-act="item-edit" data-id="${i.id}">編集</button><button class="b sm danger" data-act="item-del" data-id="${i.id}">削除</button></div></td>
      </tr>`;
    }).join("")}</table></div>` : `<div class="empty">該当する商品はありません</div>`}</div>`;
};

function itemDialog(item, focusSale) {
  const s = S();
  const isNew = !item.id;
  const it = { status: "stock", purchaseDate: today(), purchaseShipping: 0, otherCost: 0, sku: nextSku(), source: "メルカリ", ...item };
  if (focusSale) {
    it.status = "sold";
    it.soldDate = it.soldDate || today();
    it.soldPriceUsd = it.soldPriceUsd || it.listPriceUsd || "";
    it.rateAtSale = it.rateAtSale || s.usdJpy;
    it.intlShippingJpy = it.intlShippingJpy || s.defaultIntlShipping;
  }
  const body = `
    <fieldset><legend>仕入れ</legend><div class="form">
      ${fld("sku", "SKU", it.sku)}
      ${fld("title", "商品名", it.title || "", { required: true, wide: true })}
      ${fld("status", "状態", it.status, { options: Object.entries(STATUS) })}
      ${fld("source", "仕入れ先", it.source, { options: SOURCES })}
      ${fld("sourceUrl", "仕入れ先URL", it.sourceUrl || "")}
      ${fld("purchaseDate", "仕入日", it.purchaseDate, { type: "date" })}
      ${fld("purchasePrice", "仕入れ価格（円）", it.purchasePrice ?? "", { type: "number", required: true })}
      ${fld("purchaseShipping", "国内送料・手数料（円）", it.purchaseShipping, { type: "number" })}
      ${fld("otherCost", "その他費用（修理・清掃等）", it.otherCost, { type: "number" })}
    </div></fieldset>
    <fieldset><legend>出品</legend><div class="form">
      ${fld("listDate", "出品日", it.listDate || "", { type: "date" })}
      ${fld("listPriceUsd", "出品価格（USD）", it.listPriceUsd ?? "", { type: "number" })}
      ${fld("ebayUrl", "eBay 出品URL", it.ebayUrl || "", { wide: true })}
    </div></fieldset>
    <fieldset><legend>販売（売れたら入力）</legend><div class="form">
      ${fld("soldDate", "売却日", it.soldDate || "", { type: "date" })}
      ${fld("soldPriceUsd", "販売価格（USD）", it.soldPriceUsd ?? "", { type: "number" })}
      ${fld("shippingChargedUsd", "購入者負担送料（USD）", it.shippingChargedUsd ?? "", { type: "number" })}
      ${fld("intlShippingJpy", "実際の国際送料（円）", it.intlShippingJpy ?? "", { type: "number" })}
      ${fld("rateAtSale", "売却時レート（円/USD）", it.rateAtSale ?? "", { type: "number", placeholder: String(s.usdJpy) })}
      ${fld("feeOverrideUsd", "eBay手数料 実額（USD・任意）", it.feeOverrideUsd ?? "", { type: "number", placeholder: "空欄なら自動計算" })}
      ${fld("buyer", "購入者・注文番号", it.buyer || "")}
      ${fld("tracking", "追跡番号", it.tracking || "")}
    </div></fieldset>
    <div class="form">${fld("memo", "メモ", it.memo || "", { type: "textarea", wide: true })}</div>
    <div id="itemPreview"></div>`;
  openDialog(isNew ? "仕入れを登録" : focusSale ? "販売を記録" : "商品を編集", body, d => {
    if ((d.status === "sold" || d.status === "shipped") && (!d.soldDate || !n(d.soldPriceUsd))) {
      toast("売却済にするには売却日と販売価格を入力してください");
      return false;
    }
    if (d.status === "sold" || d.status === "shipped") d.rateAtSale = d.rateAtSale || s.usdJpy;
    if (isNew) {
      state.items.push({ id: uid(), ...d, createdAt: today() });
      // 候補リストから仕入れた場合は候補から外す
      if (item.fromCandidate) state.candidates = state.candidates.filter(c => c.id !== item.fromCandidate);
    }
    else Object.assign(state.items.find(x => x.id === item.id), d);
    save(); render();
    toast(isNew ? "登録しました" : "保存しました");
  }, form => {
    const d = formData(form);
    const sold = n(d.soldPriceUsd) > 0;
    const r = Calc.calcProfit({ sellUsd: sold ? d.soldPriceUsd : d.listPriceUsd, shipChargeUsd: sold ? d.shippingChargedUsd : 0, purchase: d.purchasePrice, purchaseShipping: d.purchaseShipping, otherCost: d.otherCost, intlShipping: d.intlShippingJpy === "" ? s.defaultIntlShipping : d.intlShippingJpy, feeOverrideUsd: d.feeOverrideUsd, rate: d.rateAtSale }, s);
    $("#itemPreview").innerHTML = n(d.soldPriceUsd) || n(d.listPriceUsd) ? `<p class="note">${sold ? "販売実績の利益" : "出品価格で売れた場合の見込み"}</p>` + profitPreview(r) : "";
  }, isNew ? "登録" : "保存");
}

// ----- 月次レポート -----
views.monthly = () => {
  const s = S(), y = ui.year;
  const months = Array.from({ length: 12 }, (_, i) => `${y}-${pad(i + 1)}`);
  const all = Calc.monthlySummary(state.items, state.expenses, s, months);
  const rows = all.filter(m => m.month.startsWith(y + "-"));
  const years = [...new Set([new Date().getFullYear(), ...all.map(m => +m.month.slice(0, 4))])].sort();
  const tot = rows.reduce((a, m) => { for (const k in m) if (typeof m[k] === "number") a[k] = (a[k] || 0) + m[k]; return a; }, {});
  tot.margin = tot.sales ? tot.grossProfit / tot.sales * 100 : 0;
  const sel = ui.month && ui.month.startsWith(y + "-") ? ui.month : (thisMonth().startsWith(y + "-") ? thisMonth() : `${y}-12`);
  ui.month = sel;
  const days = Calc.dailySummary(state.items, sel, s);
  const soldItems = state.items.filter(i => Calc.isSold(i) && (i.soldDate || "").startsWith(sel)).sort((a, b) => a.soldDate.localeCompare(b.soldDate));
  const inv = Calc.inventoryValue(state.items);
  const cols = [["sales", "売上"], ["fees", "eBay手数料"], ["payoutFees", "入金コスト"], ["cogs", "仕入原価"], ["shipping", "国際送料"], ["grossProfit", "粗利益"], ["expenses", "経費"], ["netProfit", "純利益"]];
  const cell = (m, k) => `<td class="n ${k === "grossProfit" || k === "netProfit" ? sign(m[k]) : ""}">${yen(m[k])}</td>`;
  return `<h1>月次レポート</h1>
  <div class="row" style="margin-bottom:12px">
    <select id="yearSel">${years.map(v => `<option ${v === y ? "selected" : ""}>${v}</option>`).join("")}</select>
    <button class="b" data-act="export-monthly" style="margin-left:auto">月次表をCSV出力</button>
  </div>
  <div class="grid kpis">
    <div class="kpi"><div class="l">${y}年 売上</div><div class="v">${yen(tot.sales)}</div><div class="s">${tot.soldCount}件販売</div></div>
    <div class="kpi"><div class="l">${y}年 純利益</div><div class="v ${sign(tot.netProfit)}">${yen(tot.netProfit)}</div><div class="s">粗利率 ${pct(tot.margin)}</div></div>
    <div class="kpi"><div class="l">${y}年 仕入れ</div><div class="v">${yen(tot.purchaseAmount)}</div><div class="s">${tot.purchaseCount}点</div></div>
    <div class="kpi"><div class="l">輸出消費税 還付見込（${y}年）</div><div class="v">${yen(tot.taxRefund)}</div><div class="s">${s.includeTaxRefund ? "利益に含めて計算中" : "利益には含めていません"}</div></div>
    <div class="kpi"><div class="l">現在の在庫</div><div class="v">${inv.count}点</div><div class="s">${yen(inv.amount)}</div></div>
  </div>
  <div class="card"><h2>${y}年 月別の純利益</h2>${barChart(rows.map(m => ({ label: m.month, short: +m.month.slice(5) + "月", value: m.netProfit, extra: `売上 ${yen(m.sales)}・${m.soldCount}件` })), "純利益")}</div>
  <div class="card"><h2>月別集計（行をクリックで日別表示）</h2><div class="tbl-wrap"><table>
    <tr><th>月</th><th class="n">販売数</th>${cols.map(([, l]) => `<th class="n">${l}</th>`).join("")}<th class="n">粗利率</th><th class="n">仕入れ</th></tr>
    ${rows.map(m => `<tr class="click ${m.month === sel ? "sel" : ""}" data-act="pick-month" data-m="${m.month}"><td>${+m.month.slice(5)}月</td><td class="n">${m.soldCount}</td>${cols.map(([k]) => cell(m, k)).join("")}<td class="n">${pct(m.margin)}</td><td class="n">${yen(m.purchaseAmount)}（${m.purchaseCount}点）</td></tr>`).join("")}
    <tr class="total"><td>合計</td><td class="n">${tot.soldCount}</td>${cols.map(([k]) => cell(tot, k)).join("")}<td class="n">${pct(tot.margin)}</td><td class="n">${yen(tot.purchaseAmount)}（${tot.purchaseCount}点）</td></tr>
  </table></div></div>
  <div class="grid two">
    <div class="card"><h2>${+sel.slice(5)}月の日別売上</h2>${days.length ? `<table><tr><th>日付</th><th class="n">件数</th><th class="n">売上</th><th class="n">利益</th></tr>${days.map(d => `<tr><td>${d.date}</td><td class="n">${d.soldCount}</td><td class="n">${yen(d.sales)}</td><td class="n ${sign(d.profit)}">${yen(d.profit)}</td></tr>`).join("")}</table>` : `<div class="empty">この月の販売はありません</div>`}</div>
    <div class="card"><div class="row" style="justify-content:space-between;margin-bottom:8px"><h2 style="margin:0">${+sel.slice(5)}月の販売明細</h2><button class="b sm" data-act="export-month-detail" ${soldItems.length ? "" : "disabled"}>CSV出力</button></div>${soldItems.length ? `<div class="tbl-wrap"><table><tr><th>売却日</th><th>商品名</th><th class="n">売価</th><th class="n">利益</th></tr>${soldItems.map(i => { const r = Calc.itemFigures(i, s); return `<tr><td>${i.soldDate}</td><td class="t">${esc(i.title)}</td><td class="n">${usd(r.salesUsd)}</td><td class="n ${sign(r.profit)}">${yen(r.profit)}</td></tr>`; }).join("")}</table></div>` : `<div class="empty">この月の販売はありません</div>`}</div>
  </div>`;
};

// ----- 経費 -----
views.expenses = () => {
  const m = ui.expMonth || thisMonth();
  const list = state.expenses.filter(e => (e.date || "").startsWith(m)).sort((a, b) => a.date.localeCompare(b.date));
  const total = list.reduce((a, e) => a + n(e.amount), 0);
  return `<h1>経費</h1>
  <div class="card"><h2>経費を追加</h2>
    <form id="expForm" class="form">
      ${fld("date", "日付", today(), { type: "date", required: true })}
      ${fld("category", "区分", EXPENSE_CATS[0], { options: EXPENSE_CATS })}
      ${fld("amount", "金額（円）", "", { type: "number", required: true })}
      ${fld("memo", "メモ", "")}
      <div class="row" style="align-items:flex-end"><button class="b primary" type="submit">追加</button></div>
    </form>
    <p class="note">ストア月額・梱包資材など、商品ごとに紐づかない費用を登録すると月次の純利益に反映されます。</p>
  </div>
  <div class="card">
    <div class="row" style="justify-content:space-between;margin-bottom:8px"><h2 style="margin:0">一覧</h2><input type="month" id="expMonth" value="${m}"></div>
    ${list.length ? `<table><tr><th>日付</th><th>区分</th><th>メモ</th><th class="n">金額</th><th></th></tr>${list.map(e => `<tr><td>${esc(e.date)}</td><td>${esc(e.category)}</td><td>${esc(e.memo)}</td><td class="n">${yen(e.amount)}</td><td><button class="b sm danger" data-act="exp-del" data-id="${e.id}">削除</button></td></tr>`).join("")}<tr class="total"><td colspan="3">合計</td><td class="n">${yen(total)}</td><td></td></tr></table>` : `<div class="empty">この月の経費はありません</div>`}
  </div>`;
};

// ----- 設定 -----
views.settings = () => {
  const s = S();
  return `<h1>設定</h1>
  <form id="setForm">
  <div class="card"><h2>為替レート</h2><div class="form">
    ${fld("usdJpy", "USD/JPY（円）", s.usdJpy, { type: "number" })}
    ${fld("autoRate", "起動時に自動更新", s.autoRate, { type: "checkbox" })}
    <div class="row" style="align-items:flex-end"><button class="b" type="button" data-act="fetch-rate">今すぐ取得</button></div>
  </div><p class="note">最終取得: ${esc(state.rateUpdated || "未取得")}（open.er-api.com）</p></div>
  <div class="card"><h2>手数料（ご自身のアカウントの条件に合わせてください）</h2><div class="form">
    ${fld("fvfRate", "落札手数料（%）", s.fvfRate, { type: "number" })}
    ${fld("perOrderFee", "1注文の固定手数料（USD）", s.perOrderFee, { type: "number" })}
    ${fld("intlFeeRate", "海外決済手数料（%）", s.intlFeeRate, { type: "number" })}
    ${fld("adRate", "広告費（%）", s.adRate, { type: "number" })}
    ${fld("payoutFeeRate", "入金・為替コスト（%）", s.payoutFeeRate, { type: "number" })}
    ${fld("defaultIntlShipping", "国際送料の初期値（円）", s.defaultIntlShipping, { type: "number" })}
  </div><p class="note">初期値は目安です。eBay の手数料はカテゴリ・ストア契約・出品者評価で変わるため、セラーハブの実績に合わせて調整してください。</p></div>
  <div class="card"><h2>仕入れ判定・目標</h2><div class="form">
    ${fld("minProfit", "最低利益（円）", s.minProfit, { type: "number" })}
    ${fld("minMargin", "最低利益率（%）", s.minMargin, { type: "number" })}
    ${fld("monthlyGoal", "月の純利益目標（円）", s.monthlyGoal, { type: "number" })}
    ${fld("includeTaxRefund", "輸出消費税の還付を利益に含める", s.includeTaxRefund, { type: "checkbox", wide: true })}
  </div></div>
  ${IS_DESKTOP ? "" : `<input type="hidden" name="ebayClientId" value="${esc(s.ebayClientId)}"><input type="hidden" name="ebayClientSecret" value="${esc(s.ebayClientSecret)}">`}
  <div class="card" ${IS_DESKTOP ? "" : "hidden"}><h2>eBay API（相場の自動取得）</h2><div class="form">
    ${fld("ebayClientId", "Client ID（App ID）", s.ebayClientId, { wide: true })}
    ${fld("ebayClientSecret", "Client Secret（Cert ID）", s.ebayClientSecret, { wide: true, type: "password" })}
  </div><p class="note">developer.ebay.com で無料の開発者アカウントを作成し、Production の Keyset を入力してください。入力した値はこのパソコン内にのみ保存されます。</p></div>
  <div class="row" style="margin-bottom:16px"><button class="b primary" type="submit">設定を保存</button></div>
  </form>
  <div class="card"><h2>データ管理</h2><div class="row">
    <button class="b" data-act="backup">バックアップを保存（JSON）</button>
    <button class="b" data-act="restore">バックアップから復元</button>
    <button class="b" data-act="export-items">在庫・販売データをCSV出力</button>
  </div>${IS_DESKTOP ? "" : `<p class="note">スマホ版のデータはこの端末のブラウザ内に保存されます。ブラウザのデータを消去したり、別の端末に移ったりする場合に備えて、定期的にバックアップを保存してください（最終バックアップ: ${esc(state.lastBackup || "なし")}）。PC版とデータを移すときも、このバックアップファイルを使います。</p>`}</div>`;
};

// ---------- 描画とイベント ----------
function render() {
  document.querySelectorAll(".nav").forEach(b => b.classList.toggle("on", b.dataset.tab === ui.tab));
  $("#view").innerHTML = views[ui.tab]();
  $("#rateBox").innerHTML = `1 USD = ${n(S().usdJpy).toFixed(2)} 円`;
  bindView();
}

function bindView() {
  // カード表示用に、各セルへ見出し名を付ける
  document.querySelectorAll("table.stack").forEach(t => {
    const heads = [...t.rows[0].cells].map(c => c.textContent);
    [...t.rows].slice(1).forEach(r => [...r.cells].forEach((c, i) => c.dataset.label = heads[i] || ""));
  });
  const cf = $("#candForm");
  if (cf) {
    const prev = $("#candPreview");
    cf.oninput = () => candPreview(cf, prev);
    candPreview(cf, prev);
    cf.onsubmit = e => {
      e.preventDefault();
      state.candidates.push({ id: uid(), ...formData(cf), createdAt: today() });
      save(); render(); toast("候補に追加しました");
    };
  }
  const pb = $("#pasteBox");
  // 欄に貼り付けたらすぐ読み取る
  if (pb) pb.onpaste = () => setTimeout(() => applyPasted(pb.value), 0);
  const og = $("#onlyGood");
  if (og) og.onchange = () => { ui.onlyGood = og.checked; render(); };
  const kw = $("#kw");
  if (kw) kw.onkeydown = e => { if (e.key === "Enter") doAction("ebay-api"); };

  const wf = $("#watchForm");
  if (wf) wf.onsubmit = e => {
    e.preventDefault();
    state.watches.push({ id: uid(), ...formData(wf) });
    save(); render();
  };
  document.querySelectorAll("[data-watch-sell]").forEach(el => el.onchange = () => {
    state.watches.find(w => w.id === el.dataset.watchSell).sellUsd = el.value === "" ? "" : +el.value;
    save(); render();
  });

  const is = $("#invSearch");
  if (is) is.oninput = () => {
    ui.invSearch = is.value;
    const pos = is.selectionStart;
    render();
    const el = $("#invSearch"); el.focus(); el.setSelectionRange(pos, pos);
  };
  document.querySelectorAll("[data-status]").forEach(el => el.onchange = () => {
    const it = state.items.find(i => i.id === el.dataset.status);
    if ((el.value === "sold" || el.value === "shipped") && !Calc.isSold(it)) { itemDialog(it, true); el.value = it.status; return; }
    it.status = el.value;
    if (el.value === "listed" && !it.listDate) it.listDate = today();
    save(); render();
  });

  const ys = $("#yearSel");
  if (ys) ys.onchange = () => { ui.year = +ys.value; render(); };

  const ef = $("#expForm");
  if (ef) ef.onsubmit = e => {
    e.preventDefault();
    const d = formData(ef);
    state.expenses.push({ id: uid(), ...d });
    ui.expMonth = d.date.slice(0, 7);
    save(); render(); toast("経費を追加しました");
  };
  const em = $("#expMonth");
  if (em) em.onchange = () => { ui.expMonth = em.value; render(); };

  const sf = $("#setForm");
  if (sf) sf.onsubmit = e => {
    e.preventDefault();
    const d = formData(sf);
    for (const k in d) if (d[k] === "") d[k] = Calc.DEFAULT_SETTINGS[k] ?? "";
    Object.assign(state.settings, d);
    save(); render(); toast("設定を保存しました");
  };
}

document.querySelector(".side").addEventListener("click", e => {
  const b = e.target.closest(".nav");
  if (b) { ui.tab = b.dataset.tab; render(); window.scrollTo(0, 0); }
});
$("#view").addEventListener("click", e => {
  const el = e.target.closest("[data-act]");
  if (el) doAction(el.dataset.act, el);
});

async function updateRate(silent) {
  try {
    const r = await api.fetchRate();
    state.settings.usdJpy = Math.round(r.rate * 100) / 100;
    state.rateUpdated = new Date().toLocaleString("ja-JP");
    save(); render();
    if (!silent) toast(`為替レートを更新しました（${state.settings.usdJpy}円）`);
  } catch (e) {
    if (!silent) toast(errMsg(e));
  }
}

function download(name, rows, filterName = "CSV") {
  api.saveFile({ name, content: Calc.toCsv(rows), filterName, ext: "csv" }).then(p => p && toast("保存しました: " + p));
}

// 貼り付けた文章を読み取り、利益シミュレーターに入力する
function applyPasted(text) {
  const r = Calc.parseListingText(text);
  const out = $("#pasteResult");
  if (!r.found) { toast("商品名・価格・URLを読み取れませんでした"); return; }
  // 別の商品なので、前の入力は残さず読み取れた内容で置き換える
  const f = $("#candForm");
  f.title.value = r.title;
  if (r.title) $("#kw").value = r.title;
  f.source.value = r.source && SOURCES.includes(r.source) ? r.source : "その他";
  f.sourceUrl.value = r.url;
  f.purchasePrice.value = r.price === null ? "" : r.price;
  f.purchaseShipping.value = 0;
  f.ebayPriceUsd.value = "";
  f.dispatchEvent(new Event("input"));
  const parts = [r.source || "仕入れ先不明", r.price !== null ? yen(r.price) : "価格なし", r.title ? "商品名あり" : "商品名なし"];
  out.textContent = "読み取り結果：" + parts.join("・");
  // 次に入力すべき欄へ移動（価格が取れていなければ仕入れ価格、取れていれば eBay 販売予想価格）
  const next = r.price === null ? f.purchasePrice : (r.title ? f.ebayPriceUsd : f.title);
  f.scrollIntoView({ behavior: "smooth", block: "start" });
  setTimeout(() => next.focus({ preventScroll: true }), 300);
  toast(r.price === null ? "価格が見つかりませんでした。仕入れ価格を入力してください" : "読み取りました。eBay の販売予想価格を入力してください");
}

async function doAction(act, el) {
  const id = el && el.dataset.id;
  const s = S();
  switch (act) {
    case "paste-clip": {
      let text = "";
      try { text = await navigator.clipboard.readText(); } catch (e) { /* 権限がない・非対応 */ }
      if (!text) { toast("自動で貼り付けできませんでした。下の欄に貼り付けてください"); $("#pasteBox").focus(); break; }
      $("#pasteBox").value = text;
      applyPasted(text);
      break;
    }
    case "paste-parse": applyPasted($("#pasteBox").value); break;
    case "site": {
      const k = $("#kw").value.trim();
      if (!k) return toast("キーワードを入力してください");
      api.openExternal(SEARCH_SITES[+el.dataset.i][1](encodeURIComponent(k)));
      break;
    }
    case "ebay-api": {
      const keyword = $("#kw").value.trim(), condition = $("#cond").value;
      if (!keyword) return toast("キーワードを入力してください");
      ui.research = { keyword, condition, loading: true };
      render();
      try {
        ui.research.result = await api.ebaySearch({ keyword, condition, clientId: s.ebayClientId, clientSecret: s.ebayClientSecret });
      } catch (e) { toast(errMsg(e)); }
      ui.research.loading = false;
      render();
      break;
    }
    case "watch-from-research": {
      const rs = ui.research, prices = rs.result.items.map(i => i.price + i.shipping);
      state.watches.push({ id: uid(), keyword: rs.keyword, condition: rs.condition, sellUsd: Math.round(Calc.median(prices) * 100) / 100, intlShippingJpy: s.defaultIntlShipping,
        stats: { total: rs.result.total, min: prices.length ? Math.min(...prices) : 0, median: Calc.median(prices), fetchedAt: today() } });
      save(); toast("ウォッチリストに追加しました");
      break;
    }
    case "cand-from-research": {
      const prices = ui.research.result.items.map(i => i.price + i.shipping);
      const f = $("#candForm");
      f.title.value = ui.research.keyword;
      f.ebayPriceUsd.value = Math.round(Calc.median(prices) * 100) / 100;
      f.ebayShippingUsd.value = 0;
      f.dispatchEvent(new Event("input"));
      f.purchasePrice.focus();
      f.scrollIntoView({ behavior: "smooth", block: "center" });
      break;
    }
    case "cand-del":
      if (confirm("この候補を削除しますか？")) { state.candidates = state.candidates.filter(c => c.id !== id); save(); render(); }
      break;
    case "cand-edit": {
      const c = state.candidates.find(x => x.id === id);
      openDialog("候補を編集", `<div class="form">${candFields(c)}</div><div id="dlgPrev"></div>`, d => { Object.assign(c, d); save(); render(); }, form => candPreview(form, $("#dlgPrev")));
      break;
    }
    case "cand-buy": {
      const c = state.candidates.find(x => x.id === id);
      itemDialog({ title: c.title, source: c.source, sourceUrl: c.sourceUrl, purchasePrice: c.purchasePrice, purchaseShipping: c.purchaseShipping, listPriceUsd: c.ebayPriceUsd, intlShippingJpy: c.intlShippingJpy, fromCandidate: c.id });
      break;
    }
    case "watch-open": {
      const w = state.watches.find(x => x.id === id), k = encodeURIComponent(w.keyword);
      const sites = SEARCH_SITES.filter(([name]) => BUY_SITES.includes(name));
      if (IS_DESKTOP) { sites.forEach(([, url]) => api.openExternal(url(k))); break; }
      // ブラウザは複数タブを同時に開けないため、リンク一覧から選んでもらう
      const max = n(w.sellUsd) ? Calc.maxPurchase(n(w.sellUsd), 0, n(w.intlShippingJpy), s) : null;
      openDialog(`「${esc(w.keyword)}」を探す`, `${max === null ? "" : `<p>仕入れ上限：<b class="pos">${yen(max)}</b> 以下なら利益候補</p>`}
        <div class="row links">${SEARCH_SITES.map(([name, url]) => `<a class="b" href="${esc(url(k))}" target="_blank" rel="noopener">${name}</a>`).join("")}</div>`, null, null, "閉じる");
      break;
      break;
    }
    case "watch-refresh":
    case "watch-refresh-all": {
      const targets = act === "watch-refresh" ? state.watches.filter(w => w.id === id) : state.watches;
      el.disabled = true;
      let ok = 0;
      for (const w of targets) {
        try { await refreshWatch(w); ok++; } catch (e) { toast(errMsg(e)); break; }
      }
      save(); render();
      if (ok) toast(`${ok}件の相場を更新しました`);
      break;
    }
    case "watch-del":
      if (confirm("削除しますか？")) { state.watches = state.watches.filter(w => w.id !== id); save(); render(); }
      break;
    case "inv-filter": ui.invFilter = el.dataset.f; render(); break;
    case "item-new": itemDialog({}); break;
    case "item-edit": itemDialog(state.items.find(i => i.id === id)); break;
    case "item-sold": itemDialog(state.items.find(i => i.id === id), true); break;
    case "item-del":
      if (confirm("この商品を削除しますか？（月次の集計からも消えます）")) { state.items = state.items.filter(i => i.id !== id); save(); render(); }
      break;
    case "ship": {
      const it = state.items.find(i => i.id === id);
      it.status = "shipped"; it.shippedDate = today();
      save(); render(); toast("発送済にしました");
      break;
    }
    case "pick-month": ui.month = el.dataset.m; render(); break;
    case "exp-del": state.expenses = state.expenses.filter(e => e.id !== id); save(); render(); break;
    case "fetch-rate": updateRate(false); break;
    case "export-items": {
      const head = ["SKU", "商品名", "状態", "仕入れ先", "仕入日", "仕入れ価格", "国内送料等", "その他費用", "出品日", "出品価格USD", "売却日", "販売価格USD", "購入者負担送料USD", "国際送料", "レート", "eBay手数料(円)", "入金コスト(円)", "利益", "利益率%", "購入者・注文", "追跡番号", "メモ"];
      download(`sedori-items-${today()}.csv`, [head, ...state.items.map(i => {
        const r = Calc.isSold(i) ? Calc.itemFigures(i, s) : null;
        return [i.sku, i.title, STATUS[i.status], i.source, i.purchaseDate, i.purchasePrice, i.purchaseShipping, i.otherCost, i.listDate, i.listPriceUsd, i.soldDate, i.soldPriceUsd, i.shippingChargedUsd, i.intlShippingJpy, i.rateAtSale,
          r ? r.feesJpy : "", r ? r.payoutFeeJpy : "", r ? r.profit : "", r ? r.margin.toFixed(1) : "", i.buyer, i.tracking, i.memo];
      })]);
      break;
    }
    case "export-monthly": {
      const y = ui.year, months = Array.from({ length: 12 }, (_, i) => `${y}-${pad(i + 1)}`);
      const rows = Calc.monthlySummary(state.items, state.expenses, s, months).filter(m => m.month.startsWith(y + "-"));
      download(`sedori-monthly-${y}.csv`, [["月", "販売数", "売上", "eBay手数料", "入金コスト", "仕入原価", "国際送料", "粗利益", "経費", "純利益", "粗利率%", "仕入れ点数", "仕入れ額", "消費税還付見込"],
        ...rows.map(m => [m.month, m.soldCount, m.sales, m.fees, m.payoutFees, m.cogs, m.shipping, m.grossProfit, m.expenses, m.netProfit, m.margin.toFixed(1), m.purchaseCount, m.purchaseAmount, m.taxRefund])]);
      break;
    }
    case "export-month-detail": {
      const items = state.items.filter(i => Calc.isSold(i) && (i.soldDate || "").startsWith(ui.month));
      download(`sedori-sales-${ui.month}.csv`, [["売却日", "SKU", "商品名", "販売額USD", "レート", "売上(円)", "eBay手数料", "入金コスト", "仕入れ総額", "国際送料", "利益", "利益率%"],
        ...items.map(i => { const r = Calc.itemFigures(i, s); return [i.soldDate, i.sku, i.title, r.salesUsd, r.rate, r.salesJpy, r.feesJpy, r.payoutFeeJpy, r.purchaseTotal, r.intlShipping, r.profit, r.margin.toFixed(1)]; })]);
      break;
    }
    case "backup":
      api.saveFile({ name: `sedori-backup-${today()}.json`, content: JSON.stringify(state, null, 1), filterName: "バックアップ", ext: "json" }).then(p => {
        if (!p) return;
        state.lastBackup = new Date().toLocaleString("ja-JP");
        save(); render(); toast("保存しました: " + p);
      });
      break;
    case "restore": {
      let d;
      try { d = await api.openJson(); } catch (e) { return toast(errMsg(e)); }
      if (!d) return;
      if (!Array.isArray(d.items) || !d.settings) return toast("バックアップファイルの形式が正しくありません");
      if (!confirm("現在のデータを上書きして復元しますか？")) return;
      state = normalize(d);
      save(); render(); toast("復元しました");
      break;
    }
  }
}

function normalize(d) {
  return {
    settings: { ...Calc.DEFAULT_SETTINGS, ...(d.settings || {}) },
    candidates: d.candidates || [], watches: d.watches || [], items: d.items || [], expenses: d.expenses || [],
    rateUpdated: d.rateUpdated || "",
    lastBackup: d.lastBackup || "",
  };
}

(async function init() {
  try {
    const d = await api.load();
    if (d) state = normalize(d);
  } catch (e) { toast("データの読み込みに失敗しました: " + errMsg(e)); }
  render();
  if (state.settings.autoRate) updateRate(true);
  if (!IS_DESKTOP) {
    // ブラウザがデータを自動削除しないよう永続化を依頼し、オフラインでも開けるよう Service Worker を登録
    if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
    if ("serviceWorker" in navigator && (location.protocol === "https:" || location.hostname === "localhost")) navigator.serviceWorker.register("sw.js").catch(() => {});
  }
})();
