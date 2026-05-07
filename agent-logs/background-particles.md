# Background Particles + Stronger Vignette

## Feature Description
Add floating background particles (50 soft quads that fade in/out, drift, and rotate behind the plinko board) and strengthen the existing vignette effect to create more visual interest, especially in the early game.

## Round 1 — Concerns

### The Janitor (Code Cleanliness)
- **Shader duplication**: Don't create a new shader file — reference the existing `drop_burst_multimesh.gdshader` directly
- **MultiMesh setup duplication**: A third copy of MultiMesh/QuadMesh assembly (alongside drop burst) is approaching extraction territory. Suggested a `MultiMeshParticlePool` helper
- **VisualTheme bloat**: 12 new exports may be too many — only theme-swappable values (color, opacity, enabled) belong in VisualTheme; particle-internal state should stay in the script

### The Godot Guru (Engine Best Practices)
- **Performance**: 50 MultiMesh instances is fine, but pre-allocate typed arrays, avoid per-frame object allocation
- **MultiMesh > GPUParticles3D**: Correct choice — GPUParticles3D lifecycle controls are awkward for per-particle fade in/out driven from GDScript
- **Theme change handling**: Must connect to `ThemeProvider.theme_changed` to avoid stale colors
- **No billboard**: Orthographic camera already faces quads; billboard mode is redundant and would fight rotation animation
- **Z-layering**: Correct approach. `depth_draw_never` means no self-occlusion but that's fine for background ambience

### The Architect (Dependencies & Connections)
- **Camera dependency**: Use explicit injection (`setup(camera)`) not `get_viewport().get_camera_3d()` — matches existing pattern
- **Signal cleanup**: Must disconnect from `theme_changed` in `_exit_tree()` to avoid stale references on scene reload
- **No board_switched needed**: Camera moves but orthographic frustum covers all boards
- **Scene reload**: Safe as long as signal disconnection is handled

### The Newcomer (Readability)
- **Inner class over dictionaries**: Dictionary-per-particle drops into untyped territory. An inner `class ParticleState` with typed fields is clearer
- **Magic numbers**: Luminance threshold (0.5), split ratio (70/30), alpha ranges all need named constants or exports
- **Extract alpha helper**: `_compute_alpha(particle)` keeps the _process loop readable
- **12 exports**: Acceptable given existing groups have similar counts, but needs `##` doc comments

### The Consistency Lover (Standardization)
- **`bg_particles_*` prefix**: Matches existing `drop_burst_*`, `vignette_*` patterns
- **Hidden particle convention**: Must use `Vector3(0, -9999, 0)` + `Basis.IDENTITY.scaled(Vector3.ZERO)` — both, not just one
- **Shader reuse**: Reference existing shader, don't copy
- **Hosting question**: Suggested plinko_board.gd alongside drop burst. Disagrees with main.gd hosting

### The Test Lead (Testing)
- **Worth testing**: 3-phase alpha calculation and color-picking luminance logic — pure math, easy to test
- **Not worth testing**: Drift/rotation (trivial math), spawn area, recycling trigger
- **Regression risk**: Minimal — read-only ThemeProvider access, no shared state

## Disagreements

### Where to host (Consistency Lover vs others)
- **Consistency Lover**: Should live in `plinko_board.gd` alongside drop burst (same pattern)
- **Others**: This is a global background effect, not per-board. The vignette analogy is more apt — own scene in `entities/background_particles/`
- **Resolution**: Own scene. Background particles are independent of any specific board. They exist behind ALL boards simultaneously. Putting them per-board would mean duplicating the effect or having an awkward "one board owns the background" coupling.

### VisualTheme export count (Janitor vs Newcomer)
- **Janitor**: Trim to 3-4 vars, keep internal state in the script
- **Newcomer**: 12 is acceptable given existing group sizes
- **Resolution**: ~9 exports is the right balance. All values that affect visual appearance and would need theme-specific tuning belong in VisualTheme. Truly internal constants (Z range, luminance threshold) stay in the script.

### MultiMesh factory extraction (Janitor vs project guidelines)
- **Janitor**: Extract shared helper to avoid a third copy of MultiMesh setup
- **Project guidelines**: "Don't create helpers, utilities, or abstractions for one-time operations. Three similar lines of code is better than a premature abstraction."
- **Resolution**: Skip extraction. The setup code is ~10 lines with different contexts (different mesh types, different capacities, different materials). A factory would be speculative.

## Final Plan
See plan file. Self-contained `entities/background_particles/` scene with inner ParticleState class, reusing existing shader, wired into main.gd alongside vignette.
