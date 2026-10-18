"""Kleine Markdown <-> HTML Umwandlung ohne Fremdbibliotheken."""
from __future__ import annotations

import html
import re
from html.parser import HTMLParser

_INLINE = [
    (re.compile(r"`([^`]+)`"), r"<code>\1</code>"),
    (re.compile(r"\*\*([^*]+)\*\*|__([^_]+)__"), lambda m: f"<strong>{m.group(1) or m.group(2)}</strong>"),
    (re.compile(r"\*([^*\s][^*]*)\*|(?<!\w)_([^_]+)_(?!\w)"), lambda m: f"<em>{m.group(1) or m.group(2)}</em>"),
    (re.compile(r"!\[([^\]]*)\]\(([^)\s]+)\)"), r'<img alt="\1" src="\2">'),
    (re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)"), r'<a href="\2">\1</a>'),
]
_SAFE_URL = re.compile(r"^(https?:|mailto:|#|[\w./%-]+$)", re.I)


def _inline(text: str) -> str:
    text = html.escape(text, quote=False)
    for pattern, repl in _INLINE:
        text = pattern.sub(repl, text)
    # javascript:-Links und ähnliches entfernen
    return re.sub(r'(href|src)="([^"]*)"',
                  lambda m: m.group(0) if _SAFE_URL.match(m.group(2)) else f'{m.group(1)}=""', text)


def md_to_html(md: str) -> str:
    out: list[str] = []
    lines = md.replace("\r\n", "\n").split("\n")
    i = 0
    para: list[str] = []

    def flush() -> None:
        if para:
            out.append("<p>" + _inline(" ".join(para)) + "</p>")
            para.clear()

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped.startswith("```"):
            flush()
            code = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            out.append("<pre><code>" + html.escape("\n".join(code)) + "</code></pre>")
        elif (m := re.match(r"^(#{1,6})\s+(.*)$", stripped)):
            flush()
            out.append(f"<h{len(m.group(1))}>{_inline(m.group(2))}</h{len(m.group(1))}>")
        elif re.match(r"^([-*_])\1{2,}$", stripped):
            flush()
            out.append("<hr>")
        elif stripped.startswith(">"):
            flush()
            out.append("<blockquote><p>" + _inline(stripped.lstrip("> ")) + "</p></blockquote>")
        elif re.match(r"^([-*+]|\d+\.)\s+", stripped):
            flush()
            ordered = bool(re.match(r"^\d+\.", stripped))
            items = []
            while i < len(lines) and re.match(r"^\s*([-*+]|\d+\.)\s+", lines[i]):
                items.append("<li>" + _inline(re.sub(r"^\s*([-*+]|\d+\.)\s+", "", lines[i])) + "</li>")
                i += 1
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(items) + f"</{tag}>")
            continue
        elif not stripped:
            flush()
        else:
            para.append(stripped)
        i += 1
    flush()
    return "\n".join(out)


def text_to_html(text: str) -> str:
    paragraphs = [p for p in re.split(r"\n\s*\n", text.replace("\r\n", "\n")) if p.strip()]
    return "\n".join("<p>" + html.escape(p.strip()).replace("\n", "<br>") + "</p>" for p in paragraphs)


def wrap_html(body: str, title: str = "") -> str:
    return ('<!DOCTYPE html>\n<html><head><meta charset="utf-8"><title>' + html.escape(title) + "</title>"
            "<style>body{font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:12pt;line-height:1.4}"
            "pre{white-space:pre-wrap}table{border-collapse:collapse}td,th{border:1px solid #888;padding:3px 6px}"
            "</style></head><body>\n" + body + "\n</body></html>\n")


class _ToMarkdown(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.out: list[str] = []
        self.href: list[str] = []
        self.lists: list[list] = []
        self.skip = 0
        self.in_pre = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in {"script", "style", "head"}:
            self.skip += 1
        elif tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
            self.out.append("\n\n" + "#" * int(tag[1]) + " ")
        elif tag in {"p", "div", "blockquote"}:
            self.out.append("\n\n" + ("> " if tag == "blockquote" else ""))
        elif tag == "br":
            self.out.append("  \n")
        elif tag in {"strong", "b"}:
            self.out.append("**")
        elif tag in {"em", "i"}:
            self.out.append("*")
        elif tag == "code" and not self.in_pre:
            self.out.append("`")
        elif tag == "pre":
            self.in_pre = True
            self.out.append("\n\n```\n")
        elif tag == "a":
            self.href.append(a.get("href", ""))
            self.out.append("[")
        elif tag == "img":
            self.out.append(f"![{a.get('alt', '')}]({a.get('src', '')})")
        elif tag in {"ul", "ol"}:
            self.lists.append([tag, 0])
            self.out.append("\n")
        elif tag == "li" and self.lists:
            kind, count = self.lists[-1]
            self.lists[-1][1] = count + 1
            self.out.append("\n" + "  " * (len(self.lists) - 1) + (f"{count + 1}. " if kind == "ol" else "- "))
        elif tag == "hr":
            self.out.append("\n\n---\n\n")

    def handle_endtag(self, tag):
        if tag in {"script", "style", "head"}:
            self.skip = max(0, self.skip - 1)
        elif tag in {"strong", "b"}:
            self.out.append("**")
        elif tag in {"em", "i"}:
            self.out.append("*")
        elif tag == "code" and not self.in_pre:
            self.out.append("`")
        elif tag == "pre":
            self.in_pre = False
            self.out.append("\n```\n")
        elif tag == "a" and self.href:
            self.out.append(f"]({self.href.pop()})")
        elif tag in {"ul", "ol"} and self.lists:
            self.lists.pop()
            self.out.append("\n")

    def handle_data(self, data):
        if self.skip:
            return
        self.out.append(data if self.in_pre else re.sub(r"\s+", " ", data))


def html_to_md(source: str) -> str:
    parser = _ToMarkdown()
    parser.feed(source)
    text = "".join(parser.out)
    return re.sub(r"\n{3,}", "\n\n", text).strip() + "\n"


class _ToText(HTMLParser):
    BLOCKS = {"p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "tr", "ul", "ol", "hr"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.out: list[str] = []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style", "head"}:
            self.skip += 1
        elif tag in self.BLOCKS:
            self.out.append("\n\n")
        elif tag == "br":
            self.out.append("\n")
        elif tag == "li":
            self.out.append("\n- ")
        elif tag in {"td", "th"}:
            self.out.append("\t")

    def handle_endtag(self, tag):
        if tag in {"script", "style", "head"}:
            self.skip = max(0, self.skip - 1)

    def handle_data(self, data):
        if not self.skip:
            self.out.append(re.sub(r"\s+", " ", data))


def html_to_text(source: str) -> str:
    parser = _ToText()
    parser.feed(source)
    text = re.sub(r"[ \t]+\n", "\n", "".join(parser.out))
    return re.sub(r"\n{3,}", "\n\n", text).strip() + "\n"
