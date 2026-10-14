# Walkthrough: Flesh out product spec and derive backlog

## What changed
`spec.md` changed from a feature wish list into the product spec for Colorsip. No code changed.

## How we got here
1. We read the original spec and the three mockups (in the gitignored `design/`) and collected 36 open questions in 8 areas.
2. The user answered them. Those answers, plus the release split (MVP / V2 / V3), are recorded on this issue.
3. Where the user left the choice to the agent, the agent picked defaults and marked them as tunable: loupe ranges, the color-name dataset, the storage model, the PDF layout.
4. The spec ends with a backlog (§18). It was filed as three top-level release epics: MVP cs-71a6c7, V2 cs-db6fed, V3 cs-05f589. They hold 28 stories, linked with `blocked_by`.

## Structure of spec.md
- §1–2: platform and roadmap. Each section carries a release tag, and UI from later releases is hidden, never shown disabled.
- §3–10: features by area (UI surfaces, picker, colors, profiles, palettes, accessibility, onboarding, settings).
- §11: storage and file format.
- §12–15: the V2/V3 features (import/export, Smart Formats, templates, sync).
- §16–18: non-goals, open items, backlog.

## Key decisions and why
- **Colors are stored as a color space plus float components plus alpha (CSS Color 4 / DTCG).** This is lossless (no clamping, keeps the P3 gamut) and maps directly to the DTCG file format, so storage and interchange share one model. `hex` is only a fallback.
- **The library is a folder with one file per palette.** V3 sync then means moving the folder into Dropbox, OneDrive or Google Drive; no migration is needed, and a conflict affects only one palette. Machine-local state stays in UserDefaults.
- **New picks go to the front** of the target palette (user revision), so the newest color is visible without scrolling. This matches Color History, which is also newest first.
- **Smart Profiles use the app under the pointer, not the frontmost app.** The color comes from the window being sampled, which often isn't the active app.
- **The MVP has a compact editor sheet**, because the main window and its inspector don't arrive until V2.
- **ΔEOK < 0.002 counts as equal** for de-duplication. It tolerates float rounding without merging visibly different colors.
- **Contrast fix changes OKLCH lightness only**, so the hue and chroma the designer chose are kept.

## Non-obvious notes
- The mockups are in `design/`, which is gitignored and exists only in the main checkout.
- §17 lists open items for V2/V3. None of them block the MVP.
- In the filed backlog, Settings (cs-7f6ead) is also blocked by library storage (cs-39dff3), because it writes `settings.json`. That link isn't in the §18 table.
