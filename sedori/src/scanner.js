/* global ZXing, Calc */
// バーコード（JAN/EAN/UPC）の読み取り。
// ブラウザ標準の BarcodeDetector が JAN に対応していればそれを使い（Android の Chrome など）、
// なければ同梱の ZXing で読み取る（iPhone の Safari など）。
(function (root) {
  "use strict";
  const FORMATS = ["ean_13", "ean_8", "upc_a", "upc_e"];
  let zxingLoading = null;
  let session = null; // 読み取り中の状態

  function loadZxing() {
    if (root.ZXing) return Promise.resolve();
    if (!zxingLoading) {
      zxingLoading = new Promise((resolve, reject) => {
        const s = document.createElement("script");
        s.src = "vendor/zxing.min.js";
        s.onload = resolve;
        s.onerror = () => { zxingLoading = null; reject(new Error("読み取り用のプログラムを読み込めませんでした")); };
        document.head.appendChild(s);
      });
    }
    return zxingLoading;
  }

  async function makeDecoder() {
    if ("BarcodeDetector" in root) {
      try {
        const supported = await root.BarcodeDetector.getSupportedFormats();
        const formats = FORMATS.filter(f => supported.includes(f));
        if (formats.includes("ean_13")) {
          const det = new root.BarcodeDetector({ formats });
          return async source => {
            const found = await det.detect(source);
            return found.length ? found[0].rawValue : null;
          };
        }
      } catch (e) { /* 対応していなければ ZXing を使う */ }
    }
    await loadZxing();
    const hints = new Map();
    const F = ZXing.BarcodeFormat;
    hints.set(ZXing.DecodeHintType.POSSIBLE_FORMATS, [F.EAN_13, F.EAN_8, F.UPC_A, F.UPC_E]);
    hints.set(ZXing.DecodeHintType.TRY_HARDER, true);
    const reader = new ZXing.MultiFormatReader();
    reader.setHints(hints);
    return async canvas => {
      try {
        const bmp = new ZXing.BinaryBitmap(new ZXing.HybridBinarizer(new ZXing.HTMLCanvasElementLuminanceSource(canvas)));
        return reader.decodeWithState(bmp).getText();
      } catch (e) {
        return null; // 見つからない
      } finally {
        reader.reset();
      }
    };
  }

  // 映像や画像の一部をキャンバスに描く（ZXing 用。中央の帯だけ切り出すと速く正確になる）
  function drawTo(canvas, src, sw, sh, band) {
    const y = band ? Math.round(sh * 0.25) : 0;
    const h = band ? Math.round(sh * 0.5) : sh;
    const scale = Math.min(1, 1280 / sw);
    canvas.width = Math.round(sw * scale);
    canvas.height = Math.round(h * scale);
    canvas.getContext("2d", { willReadFrequently: true }).drawImage(src, 0, y, sw, h, 0, 0, canvas.width, canvas.height);
    return canvas;
  }

  function dialog() {
    let d = document.getElementById("scanDlg");
    if (d) return d;
    d = document.createElement("dialog");
    d.id = "scanDlg";
    d.innerHTML = `<div class="scan-wrap">
      <h3>バーコードを読み取る</h3>
      <div class="scan-view"><video playsinline muted></video><div class="scan-guide"></div></div>
      <p class="scan-msg" role="status">カメラを準備しています…</p>
      <div class="row scan-actions">
        <label class="b">写真から読み取る<input type="file" accept="image/*" capture="environment" hidden></label>
        <button class="b" type="button" data-scan="manual">番号を入力</button>
        <button class="b primary" type="button" data-scan="close">閉じる</button>
      </div>
      <form class="row scan-manual" hidden><input inputmode="numeric" placeholder="JANコード（13桁など）" maxlength="20"><button class="b primary">決定</button></form>
    </div>`;
    document.body.appendChild(d);
    d.addEventListener("close", stop);
    d.querySelector('[data-scan="close"]').onclick = () => d.close();
    d.querySelector('[data-scan="manual"]').onclick = () => {
      // 入力中にカメラが別のものを読み取らないよう、読み取りを止める
      if (session) session.paused = true;
      msg("番号を入力して「決定」を押してください");
      const f = d.querySelector(".scan-manual");
      f.hidden = false;
      f.querySelector("input").focus();
    };
    d.querySelector(".scan-manual").onsubmit = e => {
      e.preventDefault();
      finish(e.target.querySelector("input").value, true);
    };
    d.querySelector('input[type=file]').onchange = e => {
      const file = e.target.files[0];
      e.target.value = "";
      if (file) fromImage(file);
    };
    return d;
  }

  const msg = t => { const m = document.querySelector("#scanDlg .scan-msg"); if (m) m.textContent = t; };

  function finish(raw, typed) {
    const code = Calc.normalizeGtin(raw);
    if (!code) {
      msg(typed ? "番号が正しくありません（桁数かチェックデジットが違います）" : "読み取れましたが番号が正しくありません。もう一度かざしてください");
      return false;
    }
    if (navigator.vibrate) navigator.vibrate(80);
    const cb = session && session.onResult;
    document.getElementById("scanDlg").close();
    if (cb) cb(code);
    return true;
  }

  function stop() {
    if (!session) return;
    session.stopped = true;
    clearTimeout(session.timer);
    if (session.stream) session.stream.getTracks().forEach(t => t.stop());
    const v = document.querySelector("#scanDlg video");
    if (v) v.srcObject = null;
    session = null;
  }

  async function fromImage(file) {
    msg("写真を読み取っています…");
    const url = URL.createObjectURL(file);
    try {
      const img = await new Promise((resolve, reject) => {
        const i = new Image();
        i.onload = () => resolve(i);
        i.onerror = () => reject(new Error("画像を開けませんでした"));
        i.src = url;
      });
      const decode = session.decode || (session.decode = await makeDecoder());
      const canvas = document.createElement("canvas");
      // 写真全体 → 中央の帯 の順に試す
      for (const band of [false, true]) {
        const code = await decode(drawTo(canvas, img, img.naturalWidth, img.naturalHeight, band));
        if (code && finish(code)) return;
      }
      msg("写真からバーコードが見つかりませんでした。バーコードを大きく、ピントを合わせて撮ってください");
    } catch (e) {
      msg(e.message);
    } finally {
      URL.revokeObjectURL(url);
    }
  }

  async function open(onResult) {
    stop();
    const d = dialog();
    d.querySelector(".scan-manual").hidden = true;
    d.querySelector(".scan-manual input").value = "";
    session = { onResult, stopped: false };
    const me = session;
    d.showModal();
    try {
      me.decode = await makeDecoder();
    } catch (e) {
      msg(e.message + "。番号を入力してください");
      return;
    }
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      msg("この環境ではカメラが使えません。「写真から読み取る」か「番号を入力」を使ってください");
      return;
    }
    try {
      me.stream = await navigator.mediaDevices.getUserMedia({ audio: false, video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 }, height: { ideal: 720 } } });
    } catch (e) {
      msg(e.name === "NotAllowedError" ? "カメラの使用が許可されていません。ブラウザの設定でカメラを許可するか、「写真から読み取る」を使ってください" : "カメラを起動できませんでした。「写真から読み取る」か「番号を入力」を使ってください");
      return;
    }
    if (me.stopped) { me.stream.getTracks().forEach(t => t.stop()); return; }
    const video = d.querySelector("video");
    video.srcObject = me.stream;
    await video.play().catch(() => {});
    msg("バーコードを枠の中に横向きに合わせてください");
    const canvas = document.createElement("canvas");
    const usesDetector = "BarcodeDetector" in root && !root.ZXing;
    const tick = async () => {
      if (me.stopped) return;
      if (!me.paused && video.readyState >= 2 && video.videoWidth) {
        const src = usesDetector ? video : drawTo(canvas, video, video.videoWidth, video.videoHeight, true);
        const code = await me.decode(src).catch(() => null);
        if (code && !me.stopped && finish(code)) return;
      }
      me.timer = setTimeout(tick, 120);
    };
    tick();
  }

  root.Scanner = { open, stop };
})(typeof globalThis !== "undefined" ? globalThis : this);
