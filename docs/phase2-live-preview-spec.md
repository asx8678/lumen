# Live Preview — Behavioral Spec (for lumen-nmm.5)
**Core model:** Live Preview is *source mode + decorations*, NOT a renderer. The text buffer is ALWAYS raw Markdown — never mutate it for display. Decorations sit on top, in two classes:
- **Style (S):** style the same characters and conceal short marker tokens (`**`, `#`, `` ` ``, `>`, `==`, `~~`). On the active line: keep the styling, just un-hide the markers (dimmed).
- **Widget (W):** replace a source range with a widget that looks different (link pill, `<hr>`, image, checkbox, KaTeX). On the active line: revert fully to raw source — EXCEPT a few interactive widgets Obsidian keeps rendered (task checkboxes, block embeds).

**Core reveal rule:** a decoration is suppressed (raw source shown) when the current selection — including a bare caret — intersects the logical line(s) it occupies. Trigger = caret/selection position, recomputed on every selection change. Unit = logical line. Reveal is line-wide for inline (caret anywhere on a line reveals ALL inline decorations on that line — NOT per-element). Block widgets reveal when the caret is on their line(s).

**Per-element (Class | inactive | active-line):**
- Heading `# H` | S | big heading text, `#`+space hidden | shows `# `, still heading-sized
- Bold `**x**` | S | **x** | `**x**`, x still bold, `**` dimmed
- Italic `*x*`/`_x_` | S | *x* | markers shown, still italic
- Strikethrough `~~x~~` | S | struck | markers shown, still struck
- Highlight `==x==` | S | highlighted | markers shown, still highlighted
- Inline code `` `x` `` | S | mono+bg | backticks shown, still mono
- Link `[t](u)` | W | t (link style) | full `[t](u)` source
- Wikilink `[[N]]`/`[[N|a]]` | W | N/a | `[[…]]` source
- Image `![alt](u)`, `![[img]]` | W | rendered image | raw source (block embed widget may persist)
- Bullet `- `/`* `/`+ ` | S | • bullet+indent | bullet persists, edit item text
- Numbered `1.` | S | `1.` | `1.` (no visible toggle)
- Task `- [ ]`/`- [x]` | W* | interactive checkbox | checkbox persists (clickable), `[ ]` editable
- Blockquote `> ` | S | left bar+indent, `>` hidden | bar persists, `>` revealed on active line
- Fenced code ``` ``` ``` | S | shaded highlighted box, fences stay visible | ~unchanged
- HR `---` | W | `<hr>` | raw `---`
- Table `| … |` | W | rendered table | dedicated editable-table component (NOT the generic line rule)

**Discriminator to encode:** does the rendered form differ from source only in *styling* (→ S: keep style, reveal markers) or in *content/structure* (→ W: revert to source when active)?

**Selection:** any range intersecting a line reveals that line's source (caret = zero-width selection). Multi-line selection reverts every covered line (so copy yields real Markdown). Partial selection over a styled span reveals its markers so boundaries land on real characters. Rendered widgets are atomic ranges — caret can't sit inside concealed source; entering a widget's line flips it to source.

**Multi-line/blocks:** fenced code = always a shaded editable box, fences visible, little changes on caret entry. Blockquote bar+indent apply to whole quote; `>` concealed per line, revealed on active line. Lists: bullets/numbers persist even when active; caret in an item reveals that item's inline markers only. Tables: own editing component, not the line rule.

**Gotchas:** (1) link reveal shifts layout (full `[t](u)` incl. long URLs) — absorb reflow. (2) nested/adjacent emphasis `***x***`, `**a _b_ c**` — pair markers exactly. (3) intraword `foo_bar_baz` is NOT italic (CommonMark flanking) — don't conceal. (4) escapes `\*` = literal — conceal backslash, don't treat `*` as marker. (5) `#` heading needs `#`×1-6 at line start + space; `#tag` is a tag. (6) first-line `---…---` = frontmatter; `---` under text = setext heading; only standalone `---` = HR. (7) variable backtick runs — match fence lengths. (8) wikilink label = alias/last-path/heading; reveal restores full target incl `#`/`^`. (9) embeds are block widgets, caret steps over them. (10) caret atomicity: arrows/Home/End/selection treat concealed ranges + widgets as atomic; entering a line flips to source first. (11) `%%comments%%` + inline HTML conceal-on-inactive like markers. (12) hard line breaks (2 trailing spaces / `\`) survive round-trip. (13) unbalanced markers while typing stay raw — only balanced spans decorate. (14) PERF: decorate viewport only; on selection change recompute reveal only for lines whose active-membership changed (diff old vs new active set).

**TextKit 2 mapping:** never mutate the backing store for display; compute decorations from the tree-sitter tree. Style spans → NSAttributedString attributes + conceal marker glyph RANGES via a custom NSTextLayoutFragment that omits them from layout (zero-width font tricks are unreliable → geometry breaks). Widgets → view-backed fragments / NSTextAttachmentViewProvider. activeLines = { line : line.range ∩ anySelectionRange ≠ ∅ }; on selectionDidChange diff vs previous set, invalidate only changed lines. Atomic caret nav: adjust selection so caret skips concealed ranges/widgets while a line is inactive; entering a line clears its conceal/replace decorations first.
