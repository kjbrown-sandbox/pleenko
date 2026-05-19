# Custom Cursor — Findings & Recommendation

> Status: investigation / not started. Polish pass — slot behind gameplay & economy work
> (consistent with the tech-debt-backlog stance).

## Is it worth it?

Qualified yes — as a small polish pass, not a priority.

- **Cheap in Godot.** `Input.set_custom_mouse_cursor(image, shape, hotspot)` or the
  Project Settings default. No new nodes, no per-frame cost, no architecture. A few hours
  including art.
- **Fits the brand.** A minimalist 3D game benefits disproportionately from consistent
  micro-polish — the cursor is on screen 100% of the time, so it's high-visibility per
  unit effort.
- **Modest gameplay ROI.** This is a mostly-idle game; the player mostly *watches* coins.
  The one spatial interaction — deflector placement — is already well-communicated:
  `DeflectorEditor` draws a peg-colored ghost arrow at 50% opacity on hover, and the
  remove-X is its own screen-space element. A custom placement cursor would largely
  duplicate existing signals.

Net: do it, but scope it to states that convey *new* information rather than re-skinning
everything.

## Cursor states, ranked by value for this game

1. **Input-locked / "not now"** — Highest priority. `Main.apply_input_lock(true)` runs
   during peek animations, prestige phases, and challenge transitions, and nothing
   currently tells the player their clicks are being eaten. A busy/forbidden cursor adds
   information that exists nowhere else. Routes cleanly through the single
   `apply_input_lock` chokepoint.
2. **Interactive (hand/pointer)** — Drop buttons, upgrade rows, nav arrows, menu/dialog
   buttons. Mostly achievable via each `Control`'s `mouse_default_cursor_shape` rather
   than custom art.
3. **Default/idle** — Baseline arrow for navigation and watching; sets the tone the other
   states vary from.
4. **Deflector remove** — "X"/remove cursor over the remove-X hotspot. Lower priority
   (the X element already communicates this) but reinforces the destructive action at the
   click point.

**Skip:** a dedicated deflector-*placement* cursor — the ghost arrow already owns that
affordance; adding a cursor on top risks visual noise on an already-busy board.

## Theme constraint

Palette/theme rules (normal ↔ challenge via `ThemeProvider`) matter here. Hardware
cursors are set from a fixed image — can't be tinted per-theme like a material. Options:

- **Theme-neutral art** (monochrome + contrasting outline) that reads on every background
  shade. Simplest; no theme wiring. **Start here.**
- **Swap cursor images on `ThemeProvider.theme_changed`** (same listener pattern
  `DropSection` uses for its bonus label). More work; only needed if the challenge
  palette makes a neutral cursor disappear.

## Suggested first step

Spike the input-locked cursor state — highest value, routes through the single
`apply_input_lock` chokepoint.
