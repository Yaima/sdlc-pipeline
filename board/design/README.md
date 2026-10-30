# Board design system

The visual layer for the pipeline board, kept apart from the board's code so a retheme is one file. The current theme is Graph Cloud, the AgentTrust ID brand system (`agenttrustid/brand/DESIGN.md`): layered navy surfaces, cobalt `#5a86ff` as the primary, cyan accent, Manrope for the interface and IBM Plex Mono for code, radii 10/14/20. Both themes derive from the brand; the board follows the OS setting and the toggle overrides it. Material Design 3 role names throughout, so the mapping to any Material library (MUI, Angular Material, Material Web) is direct if the board ever moves off plain CSS.

```
tokens.css          the only file to edit for a retheme: reference palette, M3 color roles (light and dark),
                    type scale on IBM Plex, shape, spacing, elevation, motion, layout, accessibility floors
components.css      app shell, waiting band, repo sections, feature cards, stage track, chips, tables, buttons,
                    empty states; references tokens only, no literal values
preview.html        living style guide and a sample of the three screens (overview, live, rule candidates)
check-contrast.py   verifies every foreground/background pair the components use against WCAG 2.2 AA, both themes
```

Open `preview.html` in a browser to see it. `python3 board/design/check-contrast.py` exits 1 if any pair falls under the floor; the pipeline's self-test runs it.

## Retheming

1. Change the `--ref-*` values at the top of `tokens.css`. The M3 roles derive from them.
2. Change the dark block the same way; dark is a second set of role values, not a filter.
3. Run `check-contrast.py`. Fix anything it reports as LOW before touching components.
4. To change the typeface, replace `--md-ref-typeface-plain` and `--md-ref-typeface-code` and the Google Fonts link in the pages that use them. Keep two families at most, and keep the code face for values that are code (slugs, hashes, commands) and nothing else.
5. The board follows the OS color scheme; `data-theme="light"` or `"dark"` on `<html>` overrides it, which is what the toggle sets.

## Choices worth knowing

- One loud element. The waiting band (amber, left edge) is the only high-saturation surface. Everything else is paper, ink, and a teal primary, so the thing that needs a person is the thing you see first.
- Stage track. Each feature card carries the stages as a row of bars with a status glyph above each: passed in green with a check, in progress in teal with a dot, waiting on a person in amber with a pause, stopped in red with a cross, not started in grey with an open circle. This is the five-way status convention GitLab, GitHub Actions, and Argo CD share, so an engineer reads the track without learning it. The stage names are printed below.
- Status is a shape, a color, and a word. Chips carry the glyph and the text (APPROVE, needs human, running); severity counts print the number. No state is conveyed by color alone (WCAG 1.4.1).
- Flat surfaces. Elevation level 1 is a 1px outline, level 2 a short shadow. No gradients.
- Motion answers an action. The only self-starting motion is the pulse on a running chip; `prefers-reduced-motion` turns it off along with every transition.

## Type scale and where each step is used

Ten steps in use (`tokens.css` also defines display-small and body-large, unused by the board and kept for the Material mapping); components reference the step, never a size. One face for the interface (Manrope), one for code values (IBM Plex Mono).

| Step | Size | Used for |
|---|---|---|
| headline-small | 26 | screen title (`.page-title`) |
| title-large | 22 | repo name in the overview, brand name at 840px and up |
| title-medium | 16 | brand name below 840px, empty-state title |
| title-small | 14 | panel headings, table captions, waiting-band title |
| body-medium | 14 | default body: paragraphs, table cells, screen subtitle, key-value lists |
| body-small | 12.5 | secondary sentences: `.hint` under a control or for an empty list, card foot, repo meta, status line, timeline rows |
| label-large | 14 | buttons, chips, tabs |
| label-medium | 12 | rail labels, stage names on the track, severity counts, `.inferred` qualifiers next to a value |
| code | 13 | commands, paths, hashes in running text |
| code-small | 12 | the same inside chips, tables, and timelines |

Rule of thumb: a sentence is body, a word or two next to a value is label, a heading is title. If a new element does not fit a row here, pick the row with the same job rather than adding a size.

## Accessibility floors (WCAG 2.2 AA)

| Requirement | Where it lives |
|---|---|
| Text contrast 4.5:1, UI parts 3:1 (1.4.3, 1.4.11) | palette values in `tokens.css`; `check-contrast.py` enforces them |
| Focus visible, 3:1 ring, never removed (2.4.7, 2.4.11, 2.4.13) | one `:focus-visible` rule in `components.css`, `--a11y-focus-ring` |
| Target size 24x24 minimum (2.5.8) | `--a11y-target-min` on chips; buttons use `--a11y-target-comfortable` (44px); whole card is the link target |
| Not color alone (1.4.1) | chips and tracks print the state; severity prints the count |
| Reduced motion (2.3.3) | `prefers-reduced-motion` block disables animation and transitions |
| Skip link, landmarks, headings (2.4.1, 1.3.1) | `.skip-link` first in the DOM; `nav`, `main`, `section` with `aria-labelledby` |
| Live updates announced without interruption (4.1.3) | the Live list is `aria-live="polite"` |
| Horizontal scroll avoided at 320px (1.4.10) | single column under 600px; tables scroll inside `.table-wrap`, the page does not |
| Text resizes to 200% (1.4.4) | all sizes in px on a type scale, no fixed heights on text containers |

## Responsive behavior (Material 3 window size classes)

| Class | Width | Navigation | Cards | Gutter |
|---|---|---|---|---|
| compact | under 600px | bottom bar, 80px, safe-area aware | one column | 16px |
| medium | 600 to 839px | left rail, 80px (Material 3 spec: 56x32 indicator, 24px icons) | one column | 24px |
| expanded | 840 to 1199px | left rail | cards fill by width, 380px minimum (two columns) | 24px |
| large | 1200px and up | left rail; opens into a 240px drawer from 1600px | three columns; content centered and capped at 1280px, 1600px from 1600px wide, 1840px from 2000px wide | 24px |

The content column is centered between the rail and the right edge, so a wide monitor shows balanced margins rather than a left-aligned column.

On compact the stage track keeps every bar and prints only the current stage's name; the other names stay in the accessible name of the track.

## Contrast report

Generated by `check-contrast.py`. Minimum is 4.5 for text and 3.0 for UI parts.

| Use | Light | Dark |
|---|---|---|
| body text | 15.22 | 16.31 |
| secondary text | 5.42 | 9.03 |
| links, primary text | 5.74 | 6.02 |
| waiting band, changes chip | 11.49 | 10.67 |
| major severity text | 5.09 | 9.57 |
| approve chip | 10.20 | 9.85 |
| blocked chip | 12.77 | 11.09 |
| outlined chip and button borders | 3.33 | 4.11 |
