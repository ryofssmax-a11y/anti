// 依存なしの最小PDFライタ。JPEG(Uint8Array)を1ページ1枚で並べる。
function buildPdf(pages) {
  const enc = new TextEncoder();
  const chunks = [];
  const offsets = [];
  let len = 0;
  const push = (d) => {
    const b = typeof d === 'string' ? enc.encode(d) : d;
    chunks.push(b);
    len += b.length;
  };
  const obj = (n, body) => { offsets[n] = len; push(`${n} 0 obj\n`); push(body); push('\nendobj\n'); };

  push('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
  const n = pages.length;
  // 1=Catalog 2=Pages, 各ページ: page, content, image の3オブジェクト
  obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  const kids = pages.map((_, i) => `${3 + i * 3} 0 R`).join(' ');
  obj(2, `<< /Type /Pages /Kids [${kids}] /Count ${n} >>`);
  pages.forEach((p, i) => {
    const pg = 3 + i * 3, ct = pg + 1, im = pg + 2;
    // 長辺をA4相当(842pt)に正規化
    const k = 842 / Math.max(p.w, p.h);
    const W = +(p.w * k).toFixed(2), H = +(p.h * k).toFixed(2);
    obj(pg, `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Contents ${ct} 0 R /Resources << /XObject << /Im0 ${im} 0 R >> >> >>`);
    const stream = `q ${W} 0 0 ${H} 0 0 cm /Im0 Do Q`;
    obj(ct, `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
    offsets[im] = len;
    push(`${im} 0 obj\n<< /Type /XObject /Subtype /Image /Width ${p.w} /Height ${p.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${p.jpeg.length} >>\nstream\n`);
    push(p.jpeg);
    push('\nendstream\nendobj\n');
  });
  const total = 3 + n * 3;
  const xref = len;
  push(`xref\n0 ${total}\n0000000000 65535 f \n`);
  for (let i = 1; i < total; i++) push(String(offsets[i]).padStart(10, '0') + ' 00000 n \n');
  push(`trailer\n<< /Size ${total} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
  return new Blob(chunks, { type: 'application/pdf' });
}
