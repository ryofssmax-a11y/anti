'use strict';
const $ = (id) => document.getElementById(id);
const video = $('video'), statusEl = $('status'), msg = $('msg');
const pages = []; // {jpeg:Uint8Array, w, h, url}
let stream = null, busy = false;

const say = (t) => { msg.textContent = t; };

// ---------- カメラ ----------
$('startCam').onclick = async () => {
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: 'environment' }, width: { ideal: 3840 }, height: { ideal: 2160 } }, audio: false,
    });
    video.srcObject = stream;
    await video.play();
    $('shot').disabled = false;
    $('startCam').textContent = 'カメラ再開';
    watch();
  } catch (e) { say('カメラを開けません: ' + e.message); }
};

// ---------- 画質補正 ----------
function enhance(src, mode, rot) {
  const MAX = 2400;
  const k = Math.min(1, MAX / Math.max(src.videoWidth, src.videoHeight));
  let w = Math.round(src.videoWidth * k), h = Math.round(src.videoHeight * k);
  const c = document.createElement('canvas');
  const swap = rot === 90 || rot === 270;
  c.width = swap ? h : w; c.height = swap ? w : h;
  const g = c.getContext('2d', { willReadFrequently: true });
  g.translate(c.width / 2, c.height / 2);
  g.rotate(rot * Math.PI / 180);
  g.drawImage(src, -w / 2, -h / 2, w, h);
  g.setTransform(1, 0, 0, 1, 0, 0);
  if (mode === 'color') return c;

  const W = c.width, H = c.height;
  const img = g.getImageData(0, 0, W, H), d = img.data;
  const gray = new Uint8ClampedArray(W * H);
  const hist = new Uint32Array(256);
  for (let i = 0, j = 0; i < d.length; i += 4, j++) {
    const v = (d[i] * 77 + d[i + 1] * 150 + d[i + 2] * 29) >> 8;
    gray[j] = v; hist[v]++;
  }
  if (mode === 'gray') {
    // 1%〜99%でコントラストを伸ばす
    const tot = W * H; let acc = 0, lo = 0, hi = 255;
    for (let i = 0; i < 256; i++) { acc += hist[i]; if (acc > tot * 0.01) { lo = i; break; } }
    acc = 0;
    for (let i = 255; i >= 0; i--) { acc += hist[i]; if (acc > tot * 0.01) { hi = i; break; } }
    const s = 255 / Math.max(1, hi - lo);
    for (let i = 0, j = 0; i < d.length; i += 4, j++) {
      const v = Math.max(0, Math.min(255, (gray[j] - lo) * s));
      d[i] = d[i + 1] = d[i + 2] = v;
    }
  } else {
    // 適応しきい値(積分画像による局所平均)
    const I = new Float64Array((W + 1) * (H + 1));
    for (let y = 0; y < H; y++) {
      let row = 0;
      for (let x = 0; x < W; x++) {
        row += gray[y * W + x];
        I[(y + 1) * (W + 1) + x + 1] = I[y * (W + 1) + x + 1] + row;
      }
    }
    const r = Math.max(8, Math.round(Math.min(W, H) / 40));
    for (let y = 0; y < H; y++) {
      const y0 = Math.max(0, y - r), y1 = Math.min(H, y + r + 1);
      for (let x = 0; x < W; x++) {
        const x0 = Math.max(0, x - r), x1 = Math.min(W, x + r + 1);
        const sum = I[y1 * (W + 1) + x1] - I[y0 * (W + 1) + x1] - I[y1 * (W + 1) + x0] + I[y0 * (W + 1) + x0];
        const mean = sum / ((x1 - x0) * (y1 - y0));
        const v = gray[y * W + x] < mean * 0.88 ? 0 : 255;
        const i = (y * W + x) * 4;
        d[i] = d[i + 1] = d[i + 2] = v;
      }
    }
  }
  g.putImageData(img, 0, 0);
  return c;
}

async function capture() {
  if (busy || !video.videoWidth) return;
  busy = true;
  $('flash').style.opacity = 0.7; setTimeout(() => ($('flash').style.opacity = 0), 120);
  try {
    const c = enhance(video, $('mode').value, +$('rot').value);
    const blob = await new Promise((r) => c.toBlob(r, 'image/jpeg', 0.85));
    const jpeg = new Uint8Array(await blob.arrayBuffer());
    pages.push({ jpeg, w: c.width, h: c.height, url: URL.createObjectURL(blob) });
    render();
  } finally { busy = false; }
}
$('shot').onclick = capture;

// ---------- 自動撮影(めくり検知) ----------
// 小さく縮小したフレームの差分で「動いた→静止した」を検出して撮影する。
const probe = document.createElement('canvas'); probe.width = 48; probe.height = 36;
const pg = probe.getContext('2d', { willReadFrequently: true });
let prev = null, moved = false, stillSince = 0;
function watch() {
  setInterval(() => {
    if (!stream || !video.videoWidth) return;
    pg.drawImage(video, 0, 0, 48, 36);
    const d = pg.getImageData(0, 0, 48, 36).data;
    const cur = new Uint8Array(48 * 36);
    for (let i = 0, j = 0; i < d.length; i += 4, j++) cur[j] = (d[i] + d[i + 1] + d[i + 2]) / 3;
    let diff = 0;
    if (prev) { for (let i = 0; i < cur.length; i++) diff += Math.abs(cur[i] - prev[i]); diff /= cur.length; }
    prev = cur;
    if (!$('auto').checked) { statusEl.textContent = '手動'; return; }
    const now = performance.now();
    if (diff > 6) { moved = true; stillSince = 0; statusEl.textContent = 'めくり中…'; }
    else if (moved) {
      if (!stillSince) stillSince = now;
      statusEl.textContent = '静止待ち…';
      if (now - stillSince > 700) { moved = false; stillSince = 0; statusEl.textContent = '撮影!'; capture(); }
    } else statusEl.textContent = '次のページをめくってください';
  }, 150);
}

// ---------- ページ一覧 ----------
function render() {
  $('count').textContent = pages.length + ' ページ';
  $('thumbs').innerHTML = '';
  pages.forEach((p, i) => {
    const d = document.createElement('div'); d.className = 'th';
    d.innerHTML = `<img src="${p.url}"><b>${i + 1}</b>`;
    const x = document.createElement('button'); x.textContent = '×';
    x.onclick = () => { URL.revokeObjectURL(p.url); pages.splice(i, 1); render(); };
    d.appendChild(x);
    $('thumbs').appendChild(d);
  });
  const none = !pages.length;
  $('dl').disabled = none; $('up').disabled = none;
}
$('undo').onclick = () => { const p = pages.pop(); if (p) URL.revokeObjectURL(p.url); render(); };
$('clear').onclick = () => { if (pages.length && confirm('全ページ削除しますか?')) { pages.forEach((p) => URL.revokeObjectURL(p.url)); pages.length = 0; render(); } };

const fileName = () => (($('title').value.trim() || '本スキャン ' + new Date().toISOString().slice(0, 10)).replace(/[\\/:*?"<>|]/g, '_'));

$('dl').onclick = () => {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(buildPdf(pages));
  a.download = fileName() + '.pdf';
  a.click();
};

// ---------- Google Drive ----------
$('cid').value = localStorage.getItem('gcid') || '';
$('saveCid').onclick = () => { localStorage.setItem('gcid', $('cid').value.trim()); say('保存しました'); };

let token = null, tokenExp = 0;
function loadGsi() {
  return new Promise((res, rej) => {
    if (window.google && google.accounts) return res();
    const s = document.createElement('script');
    s.src = 'https://accounts.google.com/gsi/client';
    s.onload = res; s.onerror = () => rej(new Error('Googleのスクリプトを読み込めません(オフライン?)'));
    document.head.appendChild(s);
  });
}
async function getToken() {
  if (token && Date.now() < tokenExp) return token;
  const cid = localStorage.getItem('gcid');
  if (!cid) throw new Error('先に「設定」でクライアントIDを入力してください');
  await loadGsi();
  return new Promise((res, rej) => {
    google.accounts.oauth2.initTokenClient({
      client_id: cid,
      scope: 'https://www.googleapis.com/auth/drive.file',
      callback: (r) => {
        if (r.error) return rej(new Error(r.error));
        token = r.access_token; tokenExp = Date.now() + (r.expires_in - 60) * 1000; res(token);
      },
    }).requestAccessToken();
  });
}
async function api(url, opt, tk) {
  const r = await fetch(url, { ...opt, headers: { ...(opt && opt.headers), Authorization: 'Bearer ' + tk } });
  if (!r.ok) throw new Error('Drive API ' + r.status + ': ' + (await r.text()).slice(0, 200));
  return r.json();
}
async function ensureFolder(tk) {
  const name = 'BookScans';
  const q = encodeURIComponent(`name='${name}' and mimeType='application/vnd.google-apps.folder' and trashed=false`);
  const f = await api(`https://www.googleapis.com/drive/v3/files?q=${q}&fields=files(id)`, {}, tk);
  if (f.files.length) return f.files[0].id;
  const c = await api('https://www.googleapis.com/drive/v3/files?fields=id', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, mimeType: 'application/vnd.google-apps.folder' }),
  }, tk);
  return c.id;
}
function upload(tk, blob, name, parent, mimeType) {
  const meta = { name, parents: [parent] };
  if (mimeType) meta.mimeType = mimeType; // Googleドキュメントに変換→OCR
  const fd = new FormData();
  fd.append('metadata', new Blob([JSON.stringify(meta)], { type: 'application/json' }));
  fd.append('file', blob);
  return api('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink', { method: 'POST', body: fd }, tk);
}
$('up').onclick = async () => {
  $('up').disabled = true;
  try {
    say('Googleにログイン中…');
    const tk = await getToken();
    const folder = await ensureFolder(tk);
    const pdf = buildPdf(pages), name = fileName();
    say('PDFをアップロード中…');
    const f = await upload(tk, pdf, name + '.pdf', folder);
    let html = `✅ 保存しました: <a href="${f.webViewLink}" target="_blank" rel="noopener">${name}.pdf</a>`;
    if ($('ocrDoc').checked) {
      say('OCR変換中…(ページ数が多いと時間がかかります)');
      const g = await upload(tk, pdf, name + '(OCR)', folder, 'application/vnd.google-apps.document');
      html += ` / <a href="${g.webViewLink}" target="_blank" rel="noopener">OCR済みドキュメント</a>`;
    }
    html += ' → <a href="https://notebooklm.google.com/" target="_blank" rel="noopener">NotebookLMを開く</a>(ソース追加→Google ドライブ→BookScans)';
    msg.innerHTML = html;
  } catch (e) { say('失敗: ' + e.message); }
  $('up').disabled = !pages.length;
};

if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
render();
