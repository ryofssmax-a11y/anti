import type { ReactNode } from "react";

// AIの回答用の最小限のMarkdown表示（見出し・太字・箇条書き・段落）。HTMLは解釈せず文字として出す。

function inline(text: string): ReactNode[] {
  return text.split(/(\*\*[^*]+\*\*)/g).map((part, i) =>
    part.startsWith("**") && part.endsWith("**") && part.length > 4 ? <strong key={i}>{part.slice(2, -2)}</strong> : part,
  );
}

export function Markdown({ text }: { text: string }) {
  const blocks: ReactNode[] = [];
  let list: { ordered: boolean; items: string[] } | null = null;
  let para: string[] = [];

  const flushPara = () => {
    if (para.length) blocks.push(<p key={blocks.length}>{inline(para.join("\n"))}</p>);
    para = [];
  };
  const flushList = () => {
    if (list) {
      const items = list.items.map((it, i) => <li key={i}>{inline(it)}</li>);
      blocks.push(list.ordered ? <ol key={blocks.length}>{items}</ol> : <ul key={blocks.length}>{items}</ul>);
    }
    list = null;
  };

  for (const line of text.split("\n")) {
    const heading = line.match(/^(#{1,4})\s+(.*)$/);
    const bullet = line.match(/^\s*[-*・]\s+(.*)$/);
    const numbered = line.match(/^\s*\d+[.)]\s+(.*)$/);
    if (heading) {
      flushPara();
      flushList();
      const level = Math.min(heading[1].length + 2, 5);
      const H = `h${level}` as "h3" | "h4" | "h5";
      blocks.push(<H key={blocks.length}>{inline(heading[2])}</H>);
    } else if (bullet || numbered) {
      flushPara();
      const ordered = Boolean(numbered);
      if (list && list.ordered !== ordered) flushList();
      list ??= { ordered, items: [] };
      list.items.push((bullet ?? numbered)![1]);
    } else if (/^\s*(---+|\*\*\*+)\s*$/.test(line)) {
      flushPara();
      flushList();
      blocks.push(<hr key={blocks.length} />);
    } else if (!line.trim()) {
      flushPara();
      flushList();
    } else {
      flushList();
      para.push(line);
    }
  }
  flushPara();
  flushList();
  return <div className="markdown">{blocks}</div>;
}
