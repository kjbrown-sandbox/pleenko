# CLAUDE.md

## Developer Context

- I am an experienced programmer but brand new to Godot. I have no prior knowledge of Godot-specific concepts, APIs, functions, node types, signals, or documentation.
- When explaining Godot concepts, provide clear explanations rather than assuming familiarity.

## Guidelines

- When I propose a feature or approach, validate it against Godot best practices and game industry conventions before implementing. If my suggestion conflicts with established patterns, flag it and explain the recommended alternative.
- Prefer idiomatic Godot solutions (e.g., using signals over polling, scene composition over deep inheritance, built-in nodes over custom reimplementations).

## Game Description

This is an incremental/idle Plinko game. The player operates an ever-growing Plinko machine. Coins are dropped from the top and land in slots at the bottom. Each slot grants a different reward. As the player progresses, the Plinko machine expands with more pegs, slots, and reward types.

### Art Style

This is a minimalist 3D game. Use simple primitive shapes (spheres, cylinders, boxes) — no complex meshes or high-poly models. Keep visuals clean and lightweight.

### Current Phase

Grayboxing/prototype. No colors, shaders, or sound effects — keep everything as simple as possible. Visual polish comes later. Focus on core mechanics and getting the prototype functional fast.

### Core Physics Approach

Do NOT use a real physics engine for coin movement. The game needs to scale to tens of thousands of coins, so all coin paths are simulated/predetermined. Each coin falls a set distance and lands in a slot based on probability, not actual peg collisions. The pegs are purely visual. This keeps performance stable regardless of coin volume.
