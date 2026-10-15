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
