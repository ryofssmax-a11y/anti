// 利益計算・集計ロジック（画面とテストで共用）
(function (root) {
  const DEFAULT_SETTINGS = {
    usdJpy: 150,           // 為替レート（円/ドル）
    autoRate: true,        // 起動時に為替レートを自動取得
    fvfRate: 13.25,        // eBay 落札手数料 %（カテゴリにより異なる）
    perOrderFee: 0.4,      // 1注文あたりの固定手数料 USD（$10以下は $0.30）
    intlFeeRate: 1.65,     // 海外決済手数料 %
    adRate: 0,             // プロモーテッドリスティング広告費 %
    payoutFeeRate: 2,      // 入金時の為替・送金コスト %（Payoneer 等）
    defaultIntlShipping: 3000, // 国際送料の初期値（円）
    minProfit: 3000,       // 利益候補とみなす最低利益（円）
    minMargin: 15,         // 利益候補とみなす最低利益率 %
    monthlyGoal: 100000,   // 月の利益目標（円）
    includeTaxRefund: false, // 輸出消費税還付を利益に含める
    ebayClientId: "",
    ebayClientSecret: "",
  };

  const num = v => (Number.isFinite(+v) ? +v : 0);
  const round = v => Math.round(v);

  // eBay で売れたときの手取りと利益を計算する
  // item: { sellUsd, shipChargeUsd, purchase, purchaseShipping, otherCost, intlShipping, feeOverrideUsd, rate }
  function calcProfit(item, s) {
    s = { ...DEFAULT_SETTINGS, ...s };
    const rate = num(item.rate) || num(s.usdJpy);
    const salesUsd = num(item.sellUsd) + num(item.shipChargeUsd);
    let feesUsd;
    if (item.feeOverrideUsd !== undefined && item.feeOverrideUsd !== null && item.feeOverrideUsd !== "") {
      feesUsd = num(item.feeOverrideUsd);
    } else if (salesUsd <= 0) {
      feesUsd = 0;
    } else {
      const perOrder = salesUsd > 10 ? num(s.perOrderFee) : Math.min(0.3, num(s.perOrderFee));
      feesUsd = salesUsd * (num(s.fvfRate) + num(s.intlFeeRate) + num(s.adRate)) / 100 + perOrder;
    }
    const salesJpy = salesUsd * rate;
    const feesJpy = feesUsd * rate;
    const payoutFeeJpy = (salesUsd - feesUsd) * rate * num(s.payoutFeeRate) / 100;
    const netJpy = salesJpy - feesJpy - payoutFeeJpy;
    const purchaseTotal = num(item.purchase) + num(item.purchaseShipping) + num(item.otherCost);
    const intlShipping = num(item.intlShipping);
    const cost = purchaseTotal + intlShipping;
    const taxRefund = num(item.purchase) * 10 / 110; // 仕入れ価格に含まれる消費税（10%）
    // 返品・返金: 購入者への返金額（USD）と返品送料など（円）を損失として差し引く
    const refundJpy = num(item.refundUsd) * rate + num(item.returnCost);
    const profit = netJpy - cost - refundJpy + (s.includeTaxRefund ? taxRefund : 0);
    return {
      rate,
      salesUsd,
      salesJpy: round(salesJpy),
      feesUsd: Math.round(feesUsd * 100) / 100,
      feesJpy: round(feesJpy),
      payoutFeeJpy: round(payoutFeeJpy),
      netJpy: round(netJpy),
      purchaseTotal: round(purchaseTotal),
      intlShipping: round(intlShipping),
      cost: round(cost),
      taxRefund: round(taxRefund),
      refundJpy: round(refundJpy),
      profit: round(profit),
      margin: salesJpy > 0 ? profit / salesJpy * 100 : 0,
      roi: cost > 0 ? profit / cost * 100 : 0,
    };
  }

  // 目標利益を確保できる仕入れ上限（送料込みの仕入れ総額）
  function maxPurchase(sellUsd, shipChargeUsd, intlShipping, s, targetProfit) {
    s = { ...DEFAULT_SETTINGS, ...s };
    const r = calcProfit({ sellUsd, shipChargeUsd, intlShipping }, { ...s, includeTaxRefund: false });
    const target = targetProfit === undefined ? num(s.minProfit) : num(targetProfit);
    // 利益率の条件も満たす必要がある
    const byMargin = r.netJpy - r.intlShipping - r.salesJpy * num(s.minMargin) / 100;
    const byProfit = r.netJpy - r.intlShipping - target;
    return Math.max(0, round(Math.min(byProfit, byMargin)));
  }

  // 利益判定: good=仕入れ候補 / ok=利益は出る / bad=赤字
  function judge(result, s) {
    s = { ...DEFAULT_SETTINGS, ...s };
    if (result.profit >= num(s.minProfit) && result.margin >= num(s.minMargin)) return "good";
    if (result.profit > 0) return "ok";
    return "bad";
  }

  function median(values) {
    const a = values.filter(v => Number.isFinite(v)).sort((x, y) => x - y);
    if (!a.length) return 0;
    const m = Math.floor(a.length / 2);
    return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2;
  }

  // 在庫アイテムを販売実績の計算用データに変換
  function itemFigures(it, s) {
    return calcProfit({
      sellUsd: it.soldPriceUsd,
      shipChargeUsd: it.shippingChargedUsd,
      purchase: it.purchasePrice,
      purchaseShipping: it.purchaseShipping,
      otherCost: it.otherCost,
      intlShipping: it.intlShippingJpy,
      feeOverrideUsd: it.feeOverrideUsd,
      refundUsd: it.refundUsd,
      returnCost: it.returnCostJpy,
      rate: it.rateAtSale,
    }, s);
  }

  const itemCost = it => num(it.purchasePrice) + num(it.purchaseShipping) + num(it.otherCost);
  const isActive = it => it.status === "stock" || it.status === "listed";
  const daysBetween = (a, b) => Math.round((Date.parse(b) - Date.parse(a)) / 86400000);

  const isSold = it => it.status === "sold" || it.status === "shipped";
  const ym = d => (d || "").slice(0, 7);

  function emptyMonth(month) {
    return { month, soldCount: 0, sales: 0, fees: 0, payoutFees: 0, cogs: 0, shipping: 0, refunds: 0, grossProfit: 0,
      taxRefund: 0, expenses: 0, netProfit: 0, purchaseCount: 0, purchaseAmount: 0 };
  }

  // 月ごとの集計。売上は売却日、仕入れは仕入日、経費は日付で計上する
  function monthlySummary(items, expenses, s, months) {
    const map = {};
    const get = m => (map[m] = map[m] || emptyMonth(m));
    (months || []).forEach(get);
    for (const it of items) {
      if (it.status === "cancelled") continue;
      if (it.purchaseDate) {
        const m = get(ym(it.purchaseDate));
        m.purchaseCount++;
        m.purchaseAmount += num(it.purchasePrice) + num(it.purchaseShipping) + num(it.otherCost);
      }
      if (isSold(it) && it.soldDate) {
        const f = itemFigures(it, s);
        const m = get(ym(it.soldDate));
        m.soldCount++;
        m.sales += f.salesJpy;
        m.fees += f.feesJpy;
        m.payoutFees += f.payoutFeeJpy;
        m.cogs += f.purchaseTotal;
        m.shipping += f.intlShipping;
        m.refunds += f.refundJpy;
        m.grossProfit += f.profit;
        m.taxRefund += f.taxRefund;
      }
    }
    for (const e of expenses || []) {
      if (!e.date) continue;
      get(ym(e.date)).expenses += num(e.amount);
    }
    return Object.values(map)
      .map(m => ({ ...m, netProfit: m.grossProfit - m.expenses, margin: m.sales > 0 ? m.grossProfit / m.sales * 100 : 0 }))
      .sort((a, b) => a.month.localeCompare(b.month));
  }

  // 指定月の日別集計
  function dailySummary(items, month, s) {
    const map = {};
    for (const it of items) {
      if (!isSold(it) || ym(it.soldDate) !== month) continue;
      const f = itemFigures(it, s);
      const d = (map[it.soldDate] = map[it.soldDate] || { date: it.soldDate, soldCount: 0, sales: 0, profit: 0 });
      d.soldCount++;
      d.sales += f.salesJpy;
      d.profit += f.profit;
    }
    return Object.values(map).sort((a, b) => a.date.localeCompare(b.date));
  }

  function inventoryValue(items) {
    let count = 0, amount = 0;
    for (const it of items) {
      if (it.status !== "stock" && it.status !== "listed") continue;
      count++;
      amount += num(it.purchasePrice) + num(it.purchaseShipping) + num(it.otherCost);
    }
    return { count, amount };
  }

  function toCsv(rows) {
    const cell = v => {
      const t = v === null || v === undefined ? "" : String(v);
      return /[",\r\n]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t;
    };
    return "﻿" + rows.map(r => r.map(cell).join(",")).join("\r\n");
  }

  // 仕入れ先別・カテゴリ別などの成績。販売率 = 売れた数 ÷ (売れた数 + 在庫中の数)
  function breakdown(items, keyFn, s) {
    const map = {};
    for (const it of items) {
      if (it.status === "cancelled") continue;
      const k = keyFn(it) || "（未設定）";
      const g = (map[k] = map[k] || { key: k, purchased: 0, soldCount: 0, active: 0, sales: 0, profit: 0, cost: 0, days: 0, daysCount: 0 });
      g.purchased++;
      if (isActive(it)) g.active++;
      if (isSold(it)) {
        const f = itemFigures(it, s);
        g.soldCount++;
        g.sales += f.salesJpy;
        g.profit += f.profit;
        g.cost += f.cost;
        if (it.purchaseDate && it.soldDate) { g.days += Math.max(0, daysBetween(it.purchaseDate, it.soldDate)); g.daysCount++; }
      }
    }
    return Object.values(map).map(g => ({
      ...g,
      avgProfit: g.soldCount ? g.profit / g.soldCount : 0,
      margin: g.sales ? g.profit / g.sales * 100 : 0,
      roi: g.cost ? g.profit / g.cost * 100 : 0,
      avgDays: g.daysCount ? g.days / g.daysCount : null,
      sellThrough: g.soldCount + g.active ? g.soldCount / (g.soldCount + g.active) * 100 : 0,
    })).sort((a, b) => b.profit - a.profit);
  }

  // まとめ仕入れの原価を按分する。weights が全部あればその比率、なければ均等。端数は最後の商品に寄せる
  function splitCost(total, weights) {
    const n = weights.length;
    if (!n) return [];
    const w = weights.every(x => num(x) > 0) ? weights.map(num) : weights.map(() => 1);
    const sum = w.reduce((a, b) => a + b, 0);
    const out = w.map(x => Math.floor(num(total) * x / sum));
    out[n - 1] += Math.round(num(total)) - out.reduce((a, b) => a + b, 0);
    return out;
  }

  // 確定申告用: 売上原価 = 期首棚卸高 + 当期仕入高 − 期末棚卸高（キャンセル分は除く）
  function yearCogs(items, year) {
    const start = `${year}-01-01`, end = `${year}-12-31`;
    const soldBy = (it, d) => isSold(it) && it.soldDate && it.soldDate <= d;
    let opening = 0, purchases = 0, closing = 0, closingCount = 0;
    for (const it of items) {
      if (it.status === "cancelled" || !it.purchaseDate) continue;
      const c = itemCost(it);
      if (it.purchaseDate < start && !soldBy(it, `${year - 1}-12-31`)) opening += c;
      if (it.purchaseDate >= start && it.purchaseDate <= end) purchases += c;
      if (it.purchaseDate <= end && !soldBy(it, end)) { closing += c; closingCount++; }
    }
    return { year, opening, purchases, closing, closingCount, cogs: opening + purchases - closing };
  }

  // ---- 共有・コピーした文章から商品名・価格・URL・仕入れ先を読み取る ----
  const SITE_PATTERNS = [
    [/mercari\.com|merc\.li/i, "メルカリ"],
    [/paypayfleamarket\.yahoo\.co\.jp/i, "Yahoo!フリマ"],
    [/auctions\.yahoo\.co\.jp|auctions\.yahoo\.jp/i, "ヤフオク"],
    [/fril\.jp|rakuma\.rakuten/i, "ラクマ"],
    [/suruga-ya\.jp/i, "駿河屋"],
    [/hardoff\.co\.jp/i, "ハードオフ"],
    [/2ndstreet\.jp/i, "セカンドストリート"],
    [/amazon\.co\.jp|amzn\.(asia|to)/i, "Amazon"],
  ];
  const SITE_WORDS = [
    [/メルカリ|mercari/i, "メルカリ"], [/Yahoo!?フリマ|PayPayフリマ/i, "Yahoo!フリマ"],
    [/ヤフオク|Yahoo!?オークション/i, "ヤフオク"], [/ラクマ/, "ラクマ"], [/駿河屋/, "駿河屋"],
    [/ハードオフ|オフモール/, "ハードオフ"], [/セカンドストリート|2nd ?STREET/i, "セカンドストリート"],
  ];
  // 商品名から取り除く定型文（サイト名・宣伝文句など）
  const BOILERPLATE = [
    /(を|が)?メルカリで(出品|販売)?中?(です)?[!！。]*/g, /メルカリでチェック[!！]*/g, /をチェック[!！]*/g,
    /#\S+/g, /\s(by|-|\||｜)\s*(メルカリ|mercari|ヤフオク!?|Yahoo!?オークション|ラクマ|Yahoo!?フリマ|PayPayフリマ|駿河屋|Amazon)[^\n]*/gi,
    /^(メルカリ|ヤフオク!?|ラクマ|Yahoo!?フリマ)\s*[:：]\s*/gi, /中古・新品通販の?\S*/g, /フリマアプリ\S*/g,
  ];
  const PRICE_RE = /(?:(即決|現在|価格|販売価格|税込)\s*[:：]?\s*)?(?:[¥￥]\s*([\d,]{2,})|([\d,]{2,})\s*円)/g;

  function parseListingText(text) {
    const raw = String(text || "").normalize("NFKC");
    const urlMatch = raw.match(/https?:\/\/[^\s"'<>（）「」【】]+/);
    const url = urlMatch ? urlMatch[0].replace(/[)\]。、,.!]+$/, "") : "";
    let source = "";
    for (const [re, name] of SITE_PATTERNS) if (re.test(url)) { source = name; break; }
    if (!source) for (const [re, name] of SITE_WORDS) if (re.test(raw)) { source = name; break; }

    const body = raw.replace(/https?:\/\/\S+/g, " ");
    // 価格: 即決価格があればそれを優先、なければ最初に出てくる金額
    const prices = [];
    let m;
    PRICE_RE.lastIndex = 0;
    while ((m = PRICE_RE.exec(body))) {
      const v = +(m[2] || m[3]).replace(/,/g, "");
      if (v >= 10 && v < 100000000) prices.push({ v, label: m[1] || "" });
    }
    const pick = prices.find(p => p.label === "即決") || prices[0];
    const price = pick ? pick.v : null;

    // 商品名: 「」や【】で囲まれていればその中身、なければ定型文と金額を除いた一番長い行
    let title = "";
    const quoted = body.match(/「([^」]{2,})」/) || body.match(/【([^】]{4,})】/);
    if (quoted && !/^(送料|即決|新品|中古|未使用)/.test(quoted[1])) title = quoted[1];
    if (!title) {
      let t = body.replace(PRICE_RE, " ").replace(/送料(込み?|無料|別)(\(出品者負担\))?/g, " ");
      for (const re of BOILERPLATE) t = t.replace(re, " ");
      title = t.split(/\n/).map(l => l.replace(/[\s　]+/g, " ").replace(/^[\s\-|｜:：・、,]+|[\s\-|｜:：・、,]+$/g, "")).filter(Boolean)
        .sort((a, b) => b.length - a.length)[0] || "";
    }
    title = title.replace(/\s+/g, " ").trim().slice(0, 200);
    const freeShipping = /送料(込み?|無料)|出品者負担/.test(body);
    return { title, price, url, source, freeShipping, found: !!(title || price || url) };
  }

  const api = { DEFAULT_SETTINGS, calcProfit, maxPurchase, judge, median, itemFigures, isSold,
    monthlySummary, dailySummary, inventoryValue, toCsv, parseListingText, breakdown, splitCost, yearCogs };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.Calc = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
