#!/usr/bin/env python3
"""Разметка отчёта -> HTML под печать. Поддерживает ровно то, что есть в REPORT.md:
заголовки, таблицы, списки, блоки кода, жирный, код в строке, ссылки, разделители."""
import html
import re
import sys

CSS = """
@page { size: A4; margin: 20mm 18mm 22mm 18mm; }
:root { --ink:#1a1a1a; --muted:#5b5b5b; --rule:#d8d8d4; --accent:#8a3324; --bg-soft:#f6f5f2; }
* { box-sizing: border-box; }
body {
  margin:0; color:var(--ink); background:#fff;
  font: 10.5pt/1.55 "Charter","Georgia","New York",serif;
  -webkit-font-smoothing: antialiased; hyphens: auto;
}
h1,h2,h3 { font-family:"Helvetica Neue",-apple-system,sans-serif; font-weight:600; line-height:1.25; }
h1 { font-size:23pt; margin:0 0 4mm; letter-spacing:-.4pt; }
h2 {
  font-size:14pt; margin:9mm 0 3mm; padding-bottom:1.6mm;
  border-bottom:1.6pt solid var(--accent); break-after:avoid;
}
h3 { font-size:11.5pt; margin:6mm 0 2mm; color:var(--muted); break-after:avoid; }
p { margin:0 0 3mm; text-align:justify; }
ul,ol { margin:0 0 3mm; padding-left:6mm; }
li { margin-bottom:1.2mm; }
strong { font-weight:700; }
a { color:var(--ink); text-decoration:none; border-bottom:.4pt solid var(--rule); }
code {
  font-family:"SF Mono",Menlo,monospace; font-size:9pt;
  background:var(--bg-soft); padding:.3mm 1mm; border-radius:1mm;
}
pre {
  background:var(--bg-soft); border-left:2pt solid var(--rule);
  padding:2.5mm 3mm; margin:0 0 3mm; overflow:hidden; break-inside:avoid;
}
pre code { background:none; padding:0; font-size:8.5pt; line-height:1.45; }
table {
  width:100%; border-collapse:collapse; margin:0 0 4mm;
  font-size:9.5pt; break-inside:avoid;
}
th {
  text-align:left; font-family:"Helvetica Neue",sans-serif; font-weight:600; font-size:8.5pt;
  text-transform:uppercase; letter-spacing:.3pt; color:var(--muted);
  border-bottom:1pt solid var(--ink); padding:1.6mm 2mm;
}
td { padding:1.6mm 2mm; border-bottom:.4pt solid var(--rule); vertical-align:top; }
tr:last-child td { border-bottom:none; }
hr { border:none; border-top:.4pt solid var(--rule); margin:6mm 0; }
.lede { font-size:11pt; color:var(--muted); margin-bottom:6mm; }
.meta { font-size:9pt; color:var(--muted); margin-bottom:8mm; }
"""

INLINE = [
    (re.compile(r"`([^`]+)`"), lambda m: f"<code>{html.escape(m.group(1))}</code>"),
    (re.compile(r"\*\*([^*]+)\*\*"), lambda m: f"<strong>{m.group(1)}</strong>"),
    (re.compile(r"\[([^\]]+)\]\(([^)]+)\)"), lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>'),
]


def inline(text: str) -> str:
    """Код в строке прячется за подстановку ДО разбора жирного.

    Разбор по частям не годится: `**открыла `.env`**` разрывается на куски, и
    парные звёздочки не находятся — маркеры остаются видны в готовом документе.
    Ловится это только просмотром отрисованных страниц.
    """
    spans: list[str] = []

    def stash(match: re.Match) -> str:
        spans.append(match.group(1))
        return f"\x00{len(spans) - 1}\x00"

    text = re.compile(r"`([^`]+)`").sub(stash, text)
    text = html.escape(text)
    for pattern, repl in INLINE[1:]:
        text = pattern.sub(repl, text)
    for index, code in enumerate(spans):
        text = text.replace(f"\x00{index}\x00", f"<code>{html.escape(code)}</code>")
    return text


def convert(md: str) -> str:
    lines, out, i = md.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            block, i = [], i + 1
            while i < len(lines) and not lines[i].startswith("```"):
                block.append(lines[i]); i += 1
            out.append("<pre><code>" + html.escape("\n".join(block)) + "</code></pre>")
        elif line.startswith("|") and i + 1 < len(lines) and set(lines[i + 1].replace("|", "").strip()) <= set("-: "):
            head = [c.strip() for c in line.strip("|").split("|")]
            i += 2
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip("|").split("|")]); i += 1
            i -= 1
            cells = "".join(f"<th>{inline(c)}</th>" for c in head)
            body = "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in rows)
            out.append(f"<table><thead><tr>{cells}</tr></thead><tbody>{body}</tbody></table>")
        elif re.match(r"^#{1,3} ", line):
            level = len(line) - len(line.lstrip("#"))
            out.append(f"<h{level}>{inline(line[level + 1:])}</h{level}>")
        elif line.strip() == "---":
            out.append("<hr>")
        elif re.match(r"^[-*] ", line) or re.match(r"^\d+\. ", line):
            ordered = bool(re.match(r"^\d+\. ", line))
            items = []
            while i < len(lines) and (re.match(r"^[-*] ", lines[i]) or re.match(r"^\d+\. ", lines[i]) or
                                      (lines[i].startswith("  ") and lines[i].strip() and items)):
                if lines[i].startswith("  ") and not re.match(r"^\s*[-*\d]", lines[i]):
                    items[-1] += " " + lines[i].strip()
                else:
                    items.append(re.sub(r"^(?:[-*]|\d+\.) ", "", lines[i]))
                i += 1
            i -= 1
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{inline(x)}</li>" for x in items) + f"</{tag}>")
        elif line.strip():
            para = [line]
            while i + 1 < len(lines) and lines[i + 1].strip() and not re.match(r"^[#|`\-*\d]", lines[i + 1]):
                i += 1; para.append(lines[i])
            out.append(f"<p>{inline(' '.join(para))}</p>")
        i += 1
    return "\n".join(out)


def main() -> None:
    md = open(sys.argv[1], encoding="utf-8").read()
    title = md.split("\n", 1)[0].lstrip("# ").strip()
    body = convert(md)
    print(f"""<!doctype html><html lang="ru"><head><meta charset="utf-8">
<title>{html.escape(title)}</title><style>{CSS}</style></head><body>
{body}
</body></html>""")


if __name__ == "__main__":
    main()
