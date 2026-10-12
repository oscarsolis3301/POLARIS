# THE BAR — what a screen must clear

## The 3-second rule
The first impression IS the product. Three seconds, no tour guide: a stranger must be able to say
what the screen is for, what the most important thing on it is, and what to do next. One element
wins on size, weight or position and everything else defers to it. If they have to read a label to
find the point, the layout never made the point.

## Legible to a non-technician
Write for the person presenting this to stakeholders, not the person who built it. Labels name
things in the reader's words, never the table or the function they came from — no internal IDs on
the surface. A number carries its unit and its comparison ("142 open, up 12 this week"); alone it is
trivia. Empty, loading and error states say what happened and what to do — never a raw code.

## Progressive disclosure
Not everything at once: show the answer, keep the evidence one gesture away. Depth lives inline
(expand in place) or in a sheet or popover over the SAME page — never a trip somewhere else and
back, which costs the reader their place. Default to the controls most people need; the rest earn
their way out from behind "More". Nothing important hides behind a hover — touch has none.

## Icons must be self-evident
An icon that needs a caption is a failed icon. Use the shape a reader already learned (magnifier,
trash, gear), one family and one weight across the screen, and never let an icon be the only carrier
of meaning — pair anything destructive or ambiguous with a word. Every icon-only control gets a fast
tooltip (~300ms, not an eternity) naming the ACTION. Hit targets stay finger-sized on desktop too.

## Density without clutter
Technicians live here for hours; whitespace that makes a landing page airy makes a workspace feel
empty and adds a scroll to every task. Spend the real estate, do not fill it: more rows per screen,
tight line height, tabular numbers that align — with ONE type scale, two weights and one grid, so
density reads as order. Clutter is not too much information, it is information with no hierarchy.

## What AI slop looks like
Fail a screen against this list — each one reads as generated on sight:
- a generic gradient hero that says nothing
- purple-to-blue everything: the default palette nobody chose
- emoji standing in for iconography
- three font weights doing the work of one hierarchy
- equal visual weight on every element, so nothing leads
- a card grid because it was easy, not because the content is cards
- lorem-ipsum polish that collapses on real data (long names, 0 results, 4,912 rows)

## THIS PRODUCT
_(unfilled — INIT asks once: "describe the look and feel you want, in a sentence.")_
> Replace this block with one or two sentences in the owner's own words: what this should feel like,
> who is looking at it, and the nearest thing you would point at and say "like that". Until it is
> replaced this section is an empty slot, not advice — do not write design advice here.

## The verdict
Every `--saw` line is asked (never forced) to end in one of these words, plus the reason:
- **PASS** — clears every section above. Ship it.
- **WEAK** — correct and readable, but one thing is soft: hierarchy, a caption-needing icon, density.
  Name the one thing, then ship it or fix it — but say which.
- **FAIL** — a stranger cannot tell what the screen is for in 3 seconds, or it hits the slop list.

## Where to go deeper
Three skills already on this machine say it better than a copy here would: `apple-design` (motion,
gesture, materials, typography) · `frontend-design` (aesthetic direction, type, colour, escaping
templated defaults) · `make-interfaces-feel-better` (hover, shadow, radius, optical alignment).
