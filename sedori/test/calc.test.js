const test = require("node:test");
const assert = require("node:assert");
const C = require("../src/calc.js");

const s = { ...C.DEFAULT_SETTINGS, usdJpy: 150, fvfRate: 13.25, intlFeeRate: 1.65, adRate: 0, perOrderFee: 0.4, payoutFeeRate: 2 };

test("calcProfit: 手数料・送料・仕入れを差し引いた利益", () => {
  const r = C.calcProfit({ sellUsd: 100, shipChargeUsd: 0, purchase: 8000, purchaseShipping: 500, intlShipping: 2500 }, s);
  // 手数料 = 100 * 14.9% + 0.4 = 15.3 USD
  assert.strictEqual(r.feesUsd, 15.3);
  assert.strictEqual(r.salesJpy, 15000);
  assert.strictEqual(r.feesJpy, 2295);
  // 入金コスト = (100 - 15.3) * 150 * 2% = 254.1
  assert.strictEqual(r.payoutFeeJpy, 254);
  assert.strictEqual(r.cost, 11000);
  assert.strictEqual(r.profit, Math.round(15000 - 2295 - 254.1 - 11000));
  assert.strictEqual(C.judge(r, s), "ok");
});

test("calcProfit: 消費税還付を含める設定", () => {
  const base = C.calcProfit({ sellUsd: 100, purchase: 11000 }, s);
  const withTax = C.calcProfit({ sellUsd: 100, purchase: 11000 }, { ...s, includeTaxRefund: true });
  assert.strictEqual(withTax.taxRefund, 1000);
  assert.strictEqual(withTax.profit - base.profit, 1000);
});

test("calcProfit: 手数料の手入力が優先される", () => {
  const r = C.calcProfit({ sellUsd: 100, feeOverrideUsd: 10, rate: 140 }, s);
  assert.strictEqual(r.feesJpy, 1400);
  assert.strictEqual(r.rate, 140);
});

test("maxPurchase: 上限価格で仕入れると最低利益・利益率ちょうど", () => {
  const max = C.maxPurchase(100, 0, 2500, s);
  const r = C.calcProfit({ sellUsd: 100, purchase: max, intlShipping: 2500 }, s);
  assert.ok(r.profit >= s.minProfit - 1);
  assert.ok(r.margin >= s.minMargin - 0.01);
  assert.strictEqual(C.judge(r, s), "good");
  const r2 = C.calcProfit({ sellUsd: 100, purchase: max + 100, intlShipping: 2500 }, s);
  assert.notStrictEqual(C.judge(r2, s), "good");
});

test("median", () => {
  assert.strictEqual(C.median([3, 1, 2]), 2);
  assert.strictEqual(C.median([4, 1, 2, 3]), 2.5);
  assert.strictEqual(C.median([]), 0);
});

test("monthlySummary / dailySummary / inventoryValue", () => {
  const items = [
    { status: "shipped", purchaseDate: "2026-09-20", purchasePrice: 5000, soldDate: "2026-10-02", soldPriceUsd: 80, intlShippingJpy: 2000, rateAtSale: 150 },
    { status: "sold", purchaseDate: "2026-10-01", purchasePrice: 3000, purchaseShipping: 300, soldDate: "2026-10-02", soldPriceUsd: 50, rateAtSale: 150 },
    { status: "listed", purchaseDate: "2026-10-05", purchasePrice: 7000 },
    { status: "cancelled", purchaseDate: "2026-10-05", purchasePrice: 9999 },
  ];
  const expenses = [{ date: "2026-10-31", amount: 3000 }];
  const months = C.monthlySummary(items, expenses, s);
  assert.deepStrictEqual(months.map(m => m.month), ["2026-09", "2026-10"]);
  const oct = months[1];
  assert.strictEqual(oct.soldCount, 2);
  assert.strictEqual(oct.purchaseCount, 2);
  assert.strictEqual(oct.purchaseAmount, 10300);
  assert.strictEqual(oct.sales, 19500);
  const p1 = C.itemFigures(items[0], s).profit, p2 = C.itemFigures(items[1], s).profit;
  assert.strictEqual(oct.grossProfit, p1 + p2);
  assert.strictEqual(oct.netProfit, p1 + p2 - 3000);
  assert.strictEqual(months[0].soldCount, 0);

  const days = C.dailySummary(items, "2026-10", s);
  assert.strictEqual(days.length, 1);
  assert.strictEqual(days[0].soldCount, 2);

  assert.deepStrictEqual(C.inventoryValue(items), { count: 1, amount: 7000 });
});

test("toCsv: カンマ・改行・引用符をエスケープ", () => {
  assert.strictEqual(C.toCsv([["a,b", 'x"y', 1]]), '﻿"a,b","x""y",1');
});

test("parseListingText: メルカリの共有文", () => {
  const r = C.parseListingText("Nikon F3 HP ボディ 動作品 ¥12,800 #メルカリ https://jp.mercari.com/item/m12345678901");
  assert.strictEqual(r.source, "メルカリ");
  assert.strictEqual(r.price, 12800);
  assert.strictEqual(r.url, "https://jp.mercari.com/item/m12345678901");
  assert.strictEqual(r.title, "Nikon F3 HP ボディ 動作品");
});

test("parseListingText: 「」で囲まれた商品名と全角の金額", () => {
  const r = C.parseListingText("メルカリで「Canon AE-1 Program 50mm付き」をチェック！ ￥８，５００\nhttps://jp.mercari.com/item/m999");
  assert.strictEqual(r.title, "Canon AE-1 Program 50mm付き");
  assert.strictEqual(r.price, 8500);
});

test("parseListingText: ヤフオクは即決価格を優先", () => {
  const r = C.parseListingText("SONY WALKMAN WM-EX5 ジャンク - ヤフオク!\n現在 3,000円 即決 5,500円\nhttps://page.auctions.yahoo.co.jp/jp/auction/x123456789");
  assert.strictEqual(r.source, "ヤフオク");
  assert.strictEqual(r.price, 5500);
  assert.strictEqual(r.title, "SONY WALKMAN WM-EX5 ジャンク");
});

test("parseListingText: URLだけ・価格なし", () => {
  const r = C.parseListingText("https://item.fril.jp/abc123");
  assert.strictEqual(r.source, "ラクマ");
  assert.strictEqual(r.price, null);
  assert.strictEqual(r.title, "");
  assert.ok(r.found);
});

test("parseListingText: 送料込みの判定と空文字", () => {
  assert.strictEqual(C.parseListingText("Seiko 5 送料込み 4,200円").freeShipping, true);
  assert.strictEqual(C.parseListingText("Seiko 5 送料込み 4,200円").title, "Seiko 5");
  assert.strictEqual(C.parseListingText("").found, false);
});

test("返金・返品費用は利益から差し引く", () => {
  const base = C.itemFigures({ soldPriceUsd: 100, purchasePrice: 5000, rateAtSale: 150 }, s);
  const ret = C.itemFigures({ soldPriceUsd: 100, purchasePrice: 5000, rateAtSale: 150, refundUsd: 20, returnCostJpy: 1500 }, s);
  assert.strictEqual(ret.refundJpy, 20 * 150 + 1500);
  assert.strictEqual(base.profit - ret.profit, 4500);
  const m = C.monthlySummary([{ status: "shipped", soldDate: "2026-10-01", soldPriceUsd: 100, rateAtSale: 150, refundUsd: 20 }], [], s);
  assert.strictEqual(m[0].refunds, 3000);
});

test("splitCost: 比率で按分し、合計が一致する", () => {
  assert.deepStrictEqual(C.splitCost(10000, [100, 50, 50]), [5000, 2500, 2500]);
  assert.deepStrictEqual(C.splitCost(1000, [0, 0, 0]), [333, 333, 334]);
  assert.deepStrictEqual(C.splitCost(1000, [1, "", 3]), [333, 333, 334]);
  assert.strictEqual(C.splitCost(9999, [3, 7]).reduce((a, b) => a + b, 0), 9999);
});

test("breakdown: 仕入れ先別の利益・販売率・平均販売日数", () => {
  const items = [
    { source: "メルカリ", status: "shipped", purchaseDate: "2026-09-01", soldDate: "2026-09-11", soldPriceUsd: 100, purchasePrice: 5000, rateAtSale: 150 },
    { source: "メルカリ", status: "listed", purchaseDate: "2026-09-05", purchasePrice: 4000 },
    { source: "ヤフオク", status: "sold", purchaseDate: "2026-09-01", soldDate: "2026-09-21", soldPriceUsd: 50, purchasePrice: 9000, rateAtSale: 150 },
    { source: "ヤフオク", status: "cancelled", purchaseDate: "2026-09-01", purchasePrice: 1 },
  ];
  const rows = C.breakdown(items, i => i.source, s);
  const mer = rows.find(r => r.key === "メルカリ"), yah = rows.find(r => r.key === "ヤフオク");
  assert.strictEqual(rows[0].key, "メルカリ");
  assert.strictEqual(mer.sellThrough, 50);
  assert.strictEqual(mer.avgDays, 10);
  assert.strictEqual(yah.purchased, 1);
  assert.ok(yah.profit < 0);
  assert.strictEqual(yah.avgDays, 20);
});

test("yearCogs: 期首棚卸 + 当期仕入 − 期末棚卸", () => {
  const items = [
    { status: "shipped", purchaseDate: "2025-12-10", soldDate: "2026-01-05", purchasePrice: 3000 },  // 期首在庫→今年売れた
    { status: "shipped", purchaseDate: "2025-11-01", soldDate: "2025-12-01", purchasePrice: 9999 },  // 去年に完結
    { status: "shipped", purchaseDate: "2026-03-01", soldDate: "2026-04-01", purchasePrice: 5000, purchaseShipping: 500 },
    { status: "listed", purchaseDate: "2026-11-01", purchasePrice: 7000 },                           // 期末在庫
    { status: "shipped", purchaseDate: "2026-12-20", soldDate: "2027-01-10", purchasePrice: 2000 },  // 年をまたいで売れた→期末在庫
  ];
  const r = C.yearCogs(items, 2026);
  assert.strictEqual(r.opening, 3000);
  assert.strictEqual(r.purchases, 14500);
  assert.strictEqual(r.closing, 9000);
  assert.strictEqual(r.closingCount, 2);
  assert.strictEqual(r.cogs, 3000 + 14500 - 9000);
});
