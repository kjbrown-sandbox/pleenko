# Ship

Prepare changes for merge by committing, reviewing with the 5-personality agent swarm, and fixing blocking issues.

## Steps

### 1. Branch Setup

Check what branch you're on:
- If on `main`: create a new feature branch with a descriptive kebab-case name based on the uncommitted changes (e.g., `feature/target-bucket-mechanic`). Switch to it.
- If already on a feature branch: stay on it.

### 2. Commit Changes

- Run `git status` and `git diff` to understand all changes.
- Stage all modified/new files (be careful not to stage sensitive files like .env).
- Commit with a concise, descriptive message summarizing the changes.

### 3. Five-Personality Review

Get the full diff between main and HEAD with `git diff main...HEAD`.

Launch **5 agents in parallel** (one per personality). Each receives the full diff and reviews through their lens. Each reports concerns as **BLOCKING** (must fix before merge) or **ADVISORY** (nice to fix).

The five personalities:

1. **The Janitor** (Code Cleanliness): duplication, dead code, oversized files, tangled responsibilities, reuse opportunities.

2. **The Godot Guru** (Engine Best Practices): correct Godot nodes/patterns/APIs, "signals up calls down", performance (node count, per-frame work), lifecycle (ready/exit_tree/queue_free), tweens/timers/resources.

3. **The Architect** (Dependencies & Connections): how the feature connects to existing systems, signal additions/modifications, ripple effects, circular dependencies, data flow clarity.

4. **The Newcomer** (Readability & Clarity): magic numbers, cryptic names, undocumented business logic, control flow clarity, naming consistency.

5. **The Consistency Lover** (Standardization): signal naming/typing/init patterns, connection patterns (direct method refs not inline lambdas), error handling consistency, type annotations, file structure, theme variable usage (never raw Color values).

### 4. Triage Feedback

After collecting all 5 reviews, present a summary table of all BLOCKING and ADVISORY concerns. For each concern, assess whether it's genuinely blocking based on the actual code (agents sometimes flag things that aren't real issues). State your assessment clearly.

### 5. Fix Blocking Issues

Fix all genuinely blocking issues directly in the code. Make the minimal targeted fix for each.

### 6. Commit Fixes

If any fixes were made, commit them as a separate commit (e.g., "Fix review feedback: [brief description]").

### 7. Push and Create PR

- Push the branch to origin with `git push -u origin <branch-name>`
- Create a pull request using `gh pr create` with a clear title and body summarizing the changes, review findings, and fixes applied
- Print the PR URL so the user can open it in their browser

### 8. Report

Tell the user:
- The PR URL (prominently, at the top)
- Summary of commits
- Which blocking issues were fixed
- Which advisory issues remain (if any worth noting)
