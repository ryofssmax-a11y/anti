// 表示確認用のデモデータ（今日の日付を基準に、約1年分の仕入れ・販売を作る）
(function (root) {
  function makeDemoData(todayStr) {
    let seed = 20261016;
    const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
    const pick = a => a[Math.floor(rnd() * a.length)];
    const between = (a, b) => Math.round(a + rnd() * (b - a));
    const pad = x => String(x).padStart(2, "0");
    const base = new Date(todayStr + "T00:00:00");
    const day = offset => {
      const d = new Date(base); d.setDate(d.getDate() + offset);
      return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    };

    // [商品名, カテゴリ, 仕入れ値の範囲(円), 販売価格の範囲(USD)]
    const CATALOG = [
      ["Nikon F3 HP ボディ", "カメラ", [12000, 22000], [180, 280]],
      ["Canon AE-1 Program 50mm F1.8", "カメラ", [8000, 15000], [130, 210]],
      ["Olympus OM-1 ブラック", "カメラ", [9000, 18000], [150, 240]],
      ["Pentax K1000 + 55mm", "カメラ", [6000, 11000], [110, 170]],
      ["Fujifilm Klasse W", "カメラ", [30000, 45000], [380, 520]],
      ["Contax T2 チタンブラック", "カメラ", [60000, 85000], [650, 900]],
      ["Seiko 5 Sports 自動巻き", "時計", [5000, 9000], [80, 140]],
      ["Casio G-Shock DW-5600 初期型", "時計", [4000, 8000], [70, 130]],
      ["Citizen Promaster ダイバー", "時計", [9000, 16000], [140, 220]],
      ["Sony Walkman WM-EX5", "オーディオ", [7000, 14000], [120, 200]],
      ["Sony Discman D-50", "オーディオ", [6000, 12000], [100, 180]],
      ["Technics SL-1200MK3", "オーディオ", [35000, 50000], [420, 600]],
      ["ゲームボーイカラー 本体 クリア", "ゲーム", [4000, 7000], [60, 110]],
      ["セガサターン 本体 + ソフト3本", "ゲーム", [5000, 9000], [90, 150]],
      ["ポケモンカード 旧裏 リザードン", "ホビー", [15000, 30000], [220, 400]],
      ["ガンプラ PG 1/60 ストライク", "ホビー", [8000, 14000], [120, 190]],
      ["Shimano Stella 2500 リール", "釣具", [18000, 28000], [240, 360]],
      ["Snow Peak チタンマグ セット", "アウトドア", [3000, 6000], [55, 95]],
    ];
    const SOURCES = ["メルカリ", "ヤフオク", "ラクマ", "ハードオフ", "Yahoo!フリマ", "駿河屋", "セカンドストリート"];
    const LOCATIONS = ["棚A-1", "棚A-2", "棚B-1", "棚B-2", "押入れ箱1", "押入れ箱2"];
    const BUYERS = ["US", "UK", "DE", "AU", "CA", "FR"];

    const items = [];
    let seq = 0;
    const sku = date => `S${date.slice(2).replace(/-/g, "")}-${pad(++seq % 100)}`;

    function addItem(purchaseOffset, status, opts = {}) {
      const [title, category, pr, sr] = pick(CATALOG);
      const purchaseDate = day(purchaseOffset);
      const purchasePrice = Math.round(between(pr[0], pr[1]) / 100) * 100;
      const listPriceUsd = between(sr[0], sr[1]);
      const it = {
        id: "demo" + seq + "-" + Math.floor(rnd() * 1e6).toString(36),
        sku: sku(purchaseDate), title, category, status,
        source: pick(SOURCES), sourceUrl: "", location: pick(LOCATIONS),
        purchaseDate, purchasePrice, purchaseShipping: pick([0, 0, 500, 750, 1000]), otherCost: rnd() < 0.15 ? 1500 : 0,
        listDate: day(purchaseOffset + between(1, 4)), listPriceUsd, ebayUrl: "", memo: "",
        createdAt: purchaseDate,
      };
      if (status === "sold" || status === "shipped") {
        const soldOffset = Math.min(0, purchaseOffset + (opts.days ?? between(5, 60)));
        it.soldDate = day(soldOffset);
        it.soldPriceUsd = Math.round(listPriceUsd * (0.88 + rnd() * 0.12));
        it.shippingChargedUsd = rnd() < 0.3 ? 15 : 0;
        it.intlShippingJpy = Math.round(between(2200, 4800) / 100) * 100;
        it.rateAtSale = Math.round((143 + rnd() * 9) * 100) / 100;
        it.buyer = pick(BUYERS) + "-" + between(100000, 999999);
        if (status === "shipped") it.tracking = "EJ" + between(10000000, 99999999) + "JP";
      }
      Object.assign(it, opts.extra || {});
      items.push(it);
      return it;
    }

    // 約1年分の販売済み（ほぼ毎週数件）
    for (let w = 52; w >= 1; w--) {
      const n = between(1, 4);
      for (let k = 0; k < n; k++) addItem(-w * 7 - between(5, 40), "shipped");
    }
    // 今日売れた商品（未発送）と、最近の未発送
    addItem(-20, "sold", { days: 20 });
    addItem(-15, "sold", { days: 15 });
    addItem(-30, "sold", { days: 29 });
    // 返品・返金の例
    addItem(-90, "shipped", { days: 30, extra: { refundUsd: 25, returnCostJpy: 1800, memo: "動作不良の申告で一部返金" } });
    addItem(-150, "shipped", { days: 20, extra: { refundUsd: 60, returnCostJpy: 3200, memo: "返品・全額に近い返金" } });
    // 在庫（出品中・未出品・長期在庫）
    for (let k = 0; k < 9; k++) addItem(-between(3, 60), "listed");
    for (let k = 0; k < 3; k++) addItem(-between(120, 200), "listed");
    for (let k = 0; k < 4; k++) addItem(-between(0, 6), "stock", { extra: { listDate: "", listPriceUsd: "" } });
    // キャンセル
    addItem(-40, "cancelled", { extra: { memo: "出品者都合でキャンセル" } });

    // まとめ仕入れの例
    const lot = [["Minolta X-700 ボディ", 260, 9000], ["Rokkor 50mm F1.4", 120, 4200], ["Minolta 純正ストラップ", 20, 800]];
    lot.forEach(([title, usd, price]) => {
      const purchaseDate = day(-12);
      items.push({ id: "demolot" + (++seq), sku: sku(purchaseDate), title, category: "カメラ", status: "listed", source: "ヤフオク",
        location: "棚A-1", purchaseDate, purchasePrice: price, purchaseShipping: Math.round(1200 * usd / 400), otherCost: 0,
        listDate: day(-10), listPriceUsd: usd, memo: "まとめ仕入れ（3点・総額¥15,200）", createdAt: purchaseDate });
    });

    const candidates = [
      ["Nikon FM2 ボディ ブラック", "メルカリ", 18000, 500, 290, 0, 3000],
      ["Canon New F-1 AE", "ヤフオク", 25000, 1000, 330, 0, 3500],
      ["Sony WM-D6C プロフェッショナル", "ハードオフ", 22000, 0, 380, 0, 3000],
      ["Seiko 6139 クロノグラフ", "ラクマ", 15000, 0, 150, 0, 2500],
      ["ゲームボーイアドバンスSP 限定色", "メルカリ", 9000, 0, 95, 0, 2500],
      ["Mamiya 7 + 80mm", "ヤフオク", 160000, 1500, 1350, 0, 6000],
      ["Casio データバンク DB-55", "Yahoo!フリマ", 3500, 0, 55, 0, 2200],
      ["Daiwa セルテート 3000", "セカンドストリート", 14000, 0, 105, 0, 3200],
    ].map(([title, source, purchasePrice, purchaseShipping, ebayPriceUsd, ebayShippingUsd, intlShippingJpy], i) => ({
      id: "democ" + i, title, source, sourceUrl: "", purchasePrice, purchaseShipping, ebayPriceUsd, ebayShippingUsd, intlShippingJpy, createdAt: day(-i),
    }));

    const watches = [
      ["Contax T3", "used", 1150, 3500, 1120, 980],
      ["Leica M6", "used", 3200, 6000, 3150, 2800],
      ["Sony WM-DD9", "used", 420, 3000, 410, 350],
      ["Rolex Tudor Submariner", "used", 0, 4000, null, null],
      ["Nintendo Virtual Boy", "", 260, 3500, 255, 199],
    ].map(([keyword, condition, sellUsd, intlShippingJpy, median, min], i) => ({
      id: "demow" + i, keyword, condition, sellUsd: sellUsd || "", intlShippingJpy,
      stats: median === null ? undefined : { total: between(20, 300), min, median, fetchedAt: day(-1) },
    }));

    const expenses = [];
    for (let m = 11; m >= 0; m--) {
      const d = new Date(base.getFullYear(), base.getMonth() - m, 1);
      const ym = `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
      expenses.push({ id: "demoe" + m + "a", date: ym + "-01", category: "eBayストア月額", amount: 4200, memo: "ベーシックストア" });
      expenses.push({ id: "demoe" + m + "b", date: ym + "-10", category: "梱包資材", amount: between(1500, 4500), memo: "段ボール・緩衝材" });
      if (m % 3 === 0) expenses.push({ id: "demoe" + m + "c", date: ym + "-20", category: "ツール・サブスク", amount: 1980, memo: "リサーチツール" });
    }
    const future = expenses.filter(e => e.date > todayStr).map(e => e.id);

    return { candidates, watches, items, expenses: expenses.filter(e => !future.includes(e.id)), isDemo: true };
  }
  if (typeof module !== "undefined" && module.exports) module.exports = { makeDemoData };
  else root.makeDemoData = makeDemoData;
})(typeof globalThis !== "undefined" ? globalThis : this);
