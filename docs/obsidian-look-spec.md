# Obsidian-look parity spec (Lumen chrome pass)

Reference target: **Obsidian default-dark**. Goal is a flat charcoal workspace
with a clear *elevation rule* — chrome (sidebar / tab bar / status bar / ribbon)
sits a few small, uniform steps **darker** than the focal editor; borders are
subtle; interaction is expressed with neutral white-washes, never the accent.

This document captures the Phase-1 **design tokens** (implemented in
`Packages/LumenDesignSystem`) plus the chrome **anatomy** and **icon** reference
that later phases (sidebar/status-bar/tabs, left ribbon, Lucide+Inter) build on.

---

## 1. Color tokens — dark (Obsidian default-dark)

Mapped onto `Palette` role names (`Palette.dark`), exposed via `ColorRole`:

| Role (`ColorRole`)        | Hex       | RGB           | Notes                                   |
|---------------------------|-----------|---------------|-----------------------------------------|
| `editorBackground`        | `#1E1E1E` | 30,30,30      | Focal content surface (lightest step)   |
| `windowBackground`        | `#161616` | 22,22,22      | Chrome (tab bar) — darker than editor   |
| `sidebarBackground`       | `#161616` | 22,22,22      | Chrome (sidebar / status bar / ribbon)  |
| `surfaceBackground`       | `#111111` | 17,17,17      | Recessed wells (search/inputs)          |
| `activeLineBackground`    | `#1A1A1A` | 26,26,26      | Active line / alternate rows            |
| `separator`               | `#2A2A2A` | 42,42,42      | Default 1px border                      |
| `separatorHover`          | `#363636` | 54,54,54      | Hover-state border                      |
| `hoverWash`               | white @ 5% | 255,255,255,.05 | Row hover wash (neutral)              |
| `activeWash`              | white @ 8% | 255,255,255,.08 | Active/pressed/selected wash (neutral)|
| `textPrimary`             | `#DADADA` | 218,218,218   | Normal text                             |
| `textSecondary`           | `#B3B3B3` | 179,179,179   | Muted (folders, inactive tabs)          |
| `textPlaceholder`         | `#666666` | 102,102,102   | Faint (counts, disabled)                |
| `linkAccent`              | `#8A7BEF` | 138,123,239   | Text/link accent (also `mdLinkText`)    |

**Elevation order (dark):** `surfaceBackground` (#111111) < `windowBackground`/
`sidebarBackground` (#161616) < `activeLineBackground` (#1A1A1A) <
`editorBackground` (#1E1E1E). Verified by `ThemeTests.testDarkElevationOrdering`.

## 2. Color tokens — light (lightly aligned)

Same role model, kept fully working: chrome `#F0F0F2` (240,240,242), wells
`#E9E9EC` (233,233,236), editor `#FFFFFF`, alt rows `#F5F5F7`, separator
black @ 12% (hover @ 20%), hover wash black @ 4%, active wash black @ 8%,
text 28,28,30 (muted .62 / faint .34), `linkAccent` `#584AC8` (88,74,200).

## 3. Accent (unchanged)

Lumen keeps its existing **interactive accent** (configurable via
`AccentColor`, persisted by `ThemeManager`). The accent is reserved for **focus
rings, prominent buttons, and the dirty-dot** only.

> **Obsidian cue (important):** do **NOT** use the accent to fill active-file /
> active-tab backgrounds. Those use the **neutral** white-wash
> (`activeLineBackground` #1A1A1A or `activeWash` white@8%). The separate
> **text/link** accent is `linkAccent` (~`#8A7BEF`), distinct from the
> interactive accent.

## 4. Radius scale (`Radius`)

| Token           | Value | Use                                  |
|-----------------|-------|--------------------------------------|
| `Radius.small`  | 4     | Selection highlights, nav rows, inputs |
| `Radius.medium` | 8     | Buttons, tab top corners             |
| `Radius.large`  | 12    | Panels, popovers, modals             |

## 5. Spacing scale (`Spacing`) — 4px base grid

`4 / 8 / 12 / 16 / 20 / 24 / 32` mapped as:
`xs=4`, `sm=8`, `md=12`, `lg=16`, `xl=20`, `xxl=24`, `xxxl=32`
(`xxs=2` retained for hairline fine-tuning). Grid verified by
`ThemeTests.testSpacingOnFourPointGrid`.

## 6. UI typography (`Typography`, system font for now)

System font (bundling **Inter** is Phase 4). UI line-height ~**1.3** via
`Typography.uiLineHeightMultiple` / `Typography.uiLineSpacing(for:)`.

| Element                | Style (`Typography.Style`) | Size / weight   |
|------------------------|----------------------------|-----------------|
| File rows, tab labels  | `body`                     | 13 / regular    |
| Section headers (muted)| `sectionHeader`            | 13 / semibold   |
| Status bar             | `callout`                  | 12 / regular    |

---

## 7. Chrome anatomy (for later phases)

Left → right:

1. **Left ribbon** — 44px wide, `#161616`, 1px right border, ~18px icons.
2. **Left sidebar** — ~260px, `#161616`:
   - header action row →
   - file tree: 13px rows, ~17–24px indent/level, hover (`hoverWash`) &
     active (`activeWash`) washes, 4px (`Radius.small`) corners →
   - **bottom vault cluster**: "Vault ⌄" switcher + help + settings gear.
3. **Tabbed content** — `#1E1E1E`:
   - tab bar height ~40px; inactive tab `#161616`; **active tab `#1E1E1E`** with
     ~8px (`Radius.medium`) rounded **top** corners so it fuses into the editor;
     + new-tab; hover ×.
   - editor = centered ~700px readable column (Phase 4).
4. **Status bar** — ~24px, `#161616`, 12px muted text, right-aligned.
5. *(optional)* **Right sidebar** mirrors the left.

## 8. Icons (Lucide, 1.75px stroke, ~18px) — Phase 4

- **Ribbon:** files, search, bookmark, (graph), settings, help-circle.
- **Sidebar header:** square-pen (new note), folder-plus, arrow-up-narrow-wide
  (sort), chevrons-down-up (collapse).
- **Tabs:** plus, x, chevron-down.
- **Sidebar toggles:** panel-left, panel-right.
