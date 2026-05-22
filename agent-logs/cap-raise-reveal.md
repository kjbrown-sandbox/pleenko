# Cap-Raise Reveal — Feature Log

## Feature description

When a player first earns a raw currency *after* a prestige, max-cap "+" buttons silently appear
next to upgrades and most players never notice them. Add a celebratory non-prestige cinematic:
the coin that earns the first post-prestige raw currency gets a gentle camera zoom + time
slowdown, a doubled 360° landing burst, then each new "+" button is revealed one-by-one with a
particle explosion (cap-raise currency color) at its spot, 0.25s apart. Plays once per board tier.

## Planning — six-personality review

Six agents (Janitor, Godot Guru, Architect, Newcomer, Consistency Lover, Test Lead) evaluated a
concrete proposed design in parallel.

### Round 1 — concerns (summary)

- **Janitor:** 2D-particle code would be a 3rd duplication (autodropper, level_section, this);
  CapRaiseRevealAnimator vs PrestigeAnimator camera/time-slow duplication; `collect_cap_raise_targets`
  handshake tangles CoinValues/UpgradeSection; `_setup_cap_raise_if_needed` already duplicated.
- **Godot Guru:** two writers of `Engine.time_scale` could collide with prestige; animator writing
  `_camera` directly fights BoardManager's tween; per-particle Tweens vs pooled MultiMesh; missing
  `_exit_tree`/re-entrancy/abort handling.
- **Architect:** the real handshake race is the *predicted vs actual bucket* — if the coin lands
  elsewhere, `cap_raise_unlocked` never fires and a defer flag is stranded → soft-lock; prefer
  "wire hidden, animator reveals". PeekAnimator collision possible. Drop `prev_board_type` payload.
- **Newcomer:** trigger predicate needs a named method + WHY doc comment; signal name misleading;
  "defer flag" mysterious; "mini-prestige" must stay out of identifiers; magic numbers → theme.
- **Consistency Lover:** signal name violates convention → `cap_raise_coin_landed`; animator is a
  hybrid of AutodropperIntroAnimator structure + PrestigeAnimator `connect_board`; do NOT add
  Callable seams (inconsistent with sibling VFX animators).
- **Test Lead:** `seed_particle_radial` must be pure + RNG-injectable; extract trigger predicate
  + ordering/schedule as pure/testable; suppression handshake is the top regression risk —
  buttons must still appear if interrupted.

### Conflicts adjudicated

- **Time-scale ownership** (Guru vs Newcomer) → animator owns its own `Engine.time_scale`, but
  guards against prestige (`current_phase != NONE` bail, abort on `prestige_phase_changed`). Not a
  PrestigePhase.
- **Camera ownership** → BoardManager `begin/end_cinematic_camera` bracket (mirrors
  `_row_upgrade_camera_active`); animator writes camera between them.
- **UI particles** (MultiMesh vs ColorRect+Tween) → ColorRect+Tween; once-per-tier low volume,
  `time_scale` restored before the sequence so no slow-mo crawl.
- **Testability seams** (Test Lead vs Consistency) → no Callable seams; extract pure statics
  (`seed_particle_radial`, `compute_reveal_schedule`) + test predicate in a headless scene.
- **OnboardingProgress flag** → not needed; `UpgradeManager._cap_raise_available` is already
  serialized, so the trigger is naturally one-shot per board.
- **Signal name** → `cap_raise_coin_landed(coin, predicted_bucket)`, parallel to `prestige_coin_landed`.

### Final plan

See `/Users/kjbrown/.claude/plans/i-ve-got-an-idea-tender-wozniak.md` (approved).

## Post-Implementation Review

_(to be appended after implementation review)_
