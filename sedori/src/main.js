const { app, BrowserWindow, ipcMain, dialog, shell } = require("electron");
const path = require("path");
const fs = require("fs");

let win;
const dataFile = () => path.join(app.getPath("userData"), "sedori-data.json");

function createWindow() {
  win = new BrowserWindow({
    width: 1280,
    height: 860,
    minWidth: 900,
    title: "eBayせどり管理",
    autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, nodeIntegration: false },
  });
  win.loadFile(path.join(__dirname, "index.html"));
  // 画面内のリンクは既定のブラウザで開く
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//.test(url)) shell.openExternal(url);
    return { action: "deny" };
  });
}

app.whenReady().then(createWindow);
app.on("window-all-closed", () => app.quit());

// ---- データの保存（userData フォルダの JSON。書き込み途中で壊れないよう一時ファイル経由） ----
ipcMain.handle("data-load", () => {
  try {
    return JSON.parse(fs.readFileSync(dataFile(), "utf8"));
  } catch (e) {
    if (e.code === "ENOENT") return null;
    // 壊れていた場合は退避して空で起動
    fs.copyFileSync(dataFile(), dataFile() + ".broken-" + Date.now());
    return null;
  }
});

ipcMain.handle("data-save", (_e, data) => {
  const tmp = dataFile() + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(data));
  fs.renameSync(tmp, dataFile());
  return true;
});

ipcMain.handle("open-external", (_e, url) => {
  if (/^https?:\/\//.test(url)) shell.openExternal(url);
});

ipcMain.handle("save-file", async (_e, { name, content, filterName, ext }) => {
  const { canceled, filePath } = await dialog.showSaveDialog(win, {
    defaultPath: path.join(app.getPath("documents"), name),
    filters: [{ name: filterName, extensions: [ext] }],
  });
  if (canceled || !filePath) return null;
  fs.writeFileSync(filePath, content);
  return filePath;
});

ipcMain.handle("open-json", async () => {
  const { canceled, filePaths } = await dialog.showOpenDialog(win, {
    filters: [{ name: "バックアップ", extensions: ["json"] }],
    properties: ["openFile"],
  });
  if (canceled || !filePaths.length) return null;
  return JSON.parse(fs.readFileSync(filePaths[0], "utf8"));
});

// ---- 為替レート（無料の open.er-api.com を使用） ----
ipcMain.handle("fetch-rate", async () => {
  const res = await fetch("https://open.er-api.com/v6/latest/USD");
  if (!res.ok) throw new Error("為替レートの取得に失敗しました (" + res.status + ")");
  const j = await res.json();
  const jpy = j && j.rates && j.rates.JPY;
  if (!jpy) throw new Error("為替レートの形式が想定外です");
  return { rate: jpy, updated: j.time_last_update_utc };
});

// ---- eBay Browse API（出品中の相場を取得） ----
let tokenCache = { key: "", token: "", exp: 0 };

async function ebayToken(clientId, clientSecret) {
  const key = clientId + ":" + clientSecret;
  if (tokenCache.key === key && Date.now() < tokenCache.exp) return tokenCache.token;
  const res = await fetch("https://api.ebay.com/identity/v1/oauth2/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: "Basic " + Buffer.from(key).toString("base64"),
    },
    body: "grant_type=client_credentials&scope=" + encodeURIComponent("https://api.ebay.com/oauth/api_scope"),
  });
  if (!res.ok) throw new Error("eBay の認証に失敗しました。設定の Client ID / Client Secret を確認してください (" + res.status + ")");
  const j = await res.json();
  tokenCache = { key, token: j.access_token, exp: Date.now() + (j.expires_in - 120) * 1000 };
  return j.access_token;
}

ipcMain.handle("ebay-search", async (_e, { keyword, clientId, clientSecret, condition }) => {
  if (!clientId || !clientSecret) throw new Error("設定画面で eBay API の Client ID と Client Secret を入力してください");
  const token = await ebayToken(clientId, clientSecret);
  const params = new URLSearchParams({ q: keyword, limit: "100" });
  const filters = ["buyingOptions:{FIXED_PRICE}", "priceCurrency:USD"];
  if (condition === "new") filters.push("conditions:{NEW}");
  if (condition === "used") filters.push("conditions:{USED}");
  params.set("filter", filters.join(","));
  const res = await fetch("https://api.ebay.com/buy/browse/v1/item_summary/search?" + params, {
    headers: { Authorization: "Bearer " + token, "X-EBAY-C-MARKETPLACE-ID": "EBAY_US" },
  });
  if (!res.ok) throw new Error("eBay 検索に失敗しました (" + res.status + ")");
  const j = await res.json();
  return {
    total: j.total || 0,
    items: (j.itemSummaries || []).map(it => ({
      title: it.title,
      price: +((it.price && it.price.value) || 0),
      shipping: +((it.shippingOptions && it.shippingOptions[0] && it.shippingOptions[0].shippingCost && it.shippingOptions[0].shippingCost.value) || 0),
      condition: it.condition || "",
      url: it.itemWebUrl,
      image: it.image && it.image.imageUrl,
      location: it.itemLocation && it.itemLocation.country,
    })),
  };
});
