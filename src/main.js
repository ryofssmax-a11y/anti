const { app, BrowserWindow, ipcMain, desktopCapturer, session, dialog, shell } = require("electron");
const path = require("path");
const fs = require("fs");
const os = require("os");
const { spawn } = require("child_process");

const ffmpegPath = require("ffmpeg-static").replace("app.asar", "app.asar.unpacked");

let win;
let capture = { sourceId: null, systemAudio: false };
let tmpFile = null;
let tmpStream = null;

function createWindow() {
  win = new BrowserWindow({
    width: 760,
    height: 720,
    title: "画面録画",
    autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, nodeIntegration: false },
  });
  win.loadFile(path.join(__dirname, "index.html"));
}

app.whenReady().then(() => {
  // getDisplayMedia() を、画面で選んだソースとシステム音声(loopback)で自動応答する
  session.defaultSession.setDisplayMediaRequestHandler(async (_req, callback) => {
    try {
      const sources = await desktopCapturer.getSources({ types: ["screen", "window"] });
      const src = sources.find(s => s.id === capture.sourceId) || sources[0];
      callback(capture.systemAudio ? { video: src, audio: "loopback" } : { video: src });
    } catch {
      callback({});
    }
  });
  createWindow();
});

app.on("window-all-closed", () => app.quit());

ipcMain.handle("list-sources", async () => {
  const sources = await desktopCapturer.getSources({
    types: ["screen", "window"],
    thumbnailSize: { width: 320, height: 180 },
  });
  return sources.map(s => ({ id: s.id, name: s.name, thumbnail: s.thumbnail.toDataURL() }));
});

ipcMain.handle("set-capture", (_e, opts) => { capture = opts; });

// 録画データは WebM としてディスクに逐次書き出し、停止後に MP4 へ変換する
ipcMain.handle("rec-start", () => {
  tmpFile = path.join(os.tmpdir(), `screenrec-${Date.now()}.webm`);
  tmpStream = fs.createWriteStream(tmpFile);
});

ipcMain.handle("rec-chunk", (_e, buf) => new Promise((res, rej) => {
  tmpStream.write(Buffer.from(buf), err => (err ? rej(err) : res()));
}));

function closeTmp() {
  return new Promise(res => (tmpStream ? tmpStream.end(res) : res()));
}

function removeTmp() {
  if (tmpFile) fs.rm(tmpFile, { force: true }, () => {});
  tmpFile = null; tmpStream = null;
}

ipcMain.handle("rec-discard", async () => { await closeTmp(); removeTmp(); });

ipcMain.handle("rec-finish", async () => {
  await closeTmp();
  const d = new Date(), p = n => String(n).padStart(2, "0");
  const name = `recording-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}.mp4`;
  const { canceled, filePath } = await dialog.showSaveDialog(win, {
    title: "録画を保存",
    defaultPath: path.join(app.getPath("videos"), name),
    filters: [{ name: "MP4 動画", extensions: ["mp4"] }],
  });
  if (canceled || !filePath) { removeTmp(); return { canceled: true }; }

  const args = [
    "-y", "-i", tmpFile,
    "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2",
    "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "160k",
    "-movflags", "+faststart",
    filePath,
  ];
  const result = await new Promise(resolve => {
    let log = "";
    const proc = spawn(ffmpegPath, args, { windowsHide: true });
    proc.stderr.on("data", c => { log = (log + c).slice(-2000); });
    proc.on("error", e => resolve({ error: e.message }));
    proc.on("close", code => resolve(code === 0 ? { path: filePath } : { error: "変換に失敗しました\n" + log }));
  });
  removeTmp();
  return result;
});

ipcMain.handle("show-in-folder", (_e, p) => shell.showItemInFolder(p));
