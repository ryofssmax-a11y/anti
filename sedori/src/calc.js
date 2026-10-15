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
    const profit = netJpy - cost + (s.includeTaxRefund ? taxRefund : 0);
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
      rate: it.rateAtSale,
    }, s);
  }

  const isSold = it => it.status === "sold" || it.status === "shipped";
  const ym = d => (d || "").slice(0, 7);

  function emptyMonth(month) {
    return { month, soldCount: 0, sales: 0, fees: 0, payoutFees: 0, cogs: 0, shipping: 0, grossProfit: 0,
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

  const api = { DEFAULT_SETTINGS, calcProfit, maxPurchase, judge, median, itemFigures, isSold,
    monthlySummary, dailySummary, inventoryValue, toCsv };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.Calc = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
