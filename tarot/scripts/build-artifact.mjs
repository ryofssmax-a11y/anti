// claude.ai のアーティファクトとして公開するための1ファイル版（dist/artifact.html）を作る。
// アーティファクトは外部ファイルを読めないので、ビルドしたCSSとJSをHTMLに埋め込む。
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

execSync("npx vite build", { stdio: "inherit" });

const dist = path.resolve("dist");
const html = fs.readFileSync(path.join(dist, "index.html"), "utf8");
const cssFile = html.match(/href="\/(assets\/[^"]+\.css)"/)[1];
const jsFile = html.match(/src="\/(assets\/[^"]+\.js)"/)[1];
const css = fs.readFileSync(path.join(dist, cssFile), "utf8");
const js = fs.readFileSync(path.join(dist, jsFile), "utf8").replace(/<\/script/gi, "<\\/script");

// 公開時に doctype/head/body が付け足されるので、中身だけを書く
const page = `<title>星読みタロット</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Shippori+Mincho:wght@500;700&family=Zen+Kaku+Gothic+New:wght@400;500;700&display=swap">
<style>${css}</style>
<div id="root"></div>
<script type="module">${js}</script>
`;
fs.writeFileSync(path.join(dist, "artifact.html"), page);
console.log(`dist/artifact.html (${(page.length / 1024).toFixed(0)} KB)`);
