---
name: project-theme-overhaul
description: UI theme overhauled from whimsical WordWANK to chaotic library aesthetic
metadata:
  type: project
---

Theme overhaul completed May 2026. Replaced cartoony fonts and bright colors with a dark library aesthetic.

**Why:** User wanted the UI to match the LOGODAL logo feel — serious, typographic, "chaotic library" rather than silly word-game whimsy.

**How to apply:** Keep this direction for any new UI components. Do not reintroduce Luckiest Guy, Fredoka, or bright `#f1c40f` yellow.

**Fonts:**
- `Cinzel` / `Cinzel Decorative` — headings, panel headers, buttons, tile point values
- `Luckiest Guy` — tile letters only (user explicitly kept the old tile font)
- `Fredoka` — tile point values only (kept with Luckiest Guy)
- `Crimson Pro` — all body/running text (chat, panels, stats, descriptions)
- `IM Fell English` — italic accent/flavor text only (system messages, subtitles)

**Palette:**
- Background: `radial-gradient(ellipse at 40% 10%, #1e1208, #0e0906, #060302)` — warm dark, not cold blue
- Accent gold: `#c9a84c` (antique, not bright `#f1c40f`)
- Panels: `#1e1208` / `#2a1c0c` (dark mahogany)
- Forest green: `#4a7c59` / `#3d6b4a` (success states)
- Crimson: `#8b2635` (errors)
- Text: `#e8d8c0` (aged cream)

**Tiles:** Original tan/wood parchment kept — `#d2b48c`/`#c19a6b` gradient, `#8b4513` border. User explicitly preferred the old tile style.

**Other changes in this session:**
- MESSAGES panel toggle moved to header icon row as 💬, second after Help
- `logodal.fazigu.org` → `logodal.com` in Manager.pm, Logodal.pm, Chart.yaml, README
- `you_are_daedalus` string updated to "You are the apex logodal!" across all 6 locales
- `error_word_not_found` changed to `{{word}} ⁉️` across all 6 locales
