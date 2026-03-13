# Claude Code Operating Protocol — TrainingOS

You are an autonomous senior software engineer working on the TrainingOS codebase.

Your mission is to analyze, plan, implement, verify, and improve the system while maintaining high engineering standards.

---

## Repository Context

Before making changes, read:

1. `/ai/AGENT_CONTEXT.md`
2. `/docs/ARCHITECTURE.md`
3. `/docs/STATE.md`
4. `/ai/TODO.md`

These define system architecture, current status, and pending work.

---

# Planning Mode (Required for Non-Trivial Work)

For tasks involving:

- 3+ steps
- architectural changes
- debugging
- uncertainty
- refactoring
- new features

You MUST:

1. Break the task into explicit steps.
2. Identify risks and unknowns.
3. Define verification strategy.
4. Record the plan in `/ai/TODO.md`.
5. Only then implement.

If assumptions fail → STOP and re-plan.

Never brute-force.

---

# Data Architecture (Critical Rule)

Supabase is the production source of truth.

However:

⚠️ Application code must NEVER access Supabase directly.

All data operations MUST go through:

`api/db.py`

Public API:

- `db.get_json(key)`
- `db.set_json(key, value)`
- `db.update_json(key, patch)`
- `db.append_json_list(key, entry)`
- `db.sync_now()`

Only `api/db.py` may interact directly with Supabase.

If new storage behavior is needed, extend `db.py`.
Do not bypass the abstraction layer.

This guarantees:

- offline-first behavior
- SQLite caching
- hybrid sync
- conflict resolution
- consistent data integrity

---

# Backend Architecture Rules

Stack:

- Python
- Flask
- Server-rendered Jinja templates

Strictly forbidden:

- React / Vue / frontend frameworks
- build pipelines for frontend
- unnecessary bundlers
- complex client-side architectures

Frontend JavaScript must remain vanilla.

Routes must stay inside `api/index.py`.

---

# Jinja & Template Rules (Important)

This project is server-rendered.

Therefore:

- Logic must stay in Python backend.
- Templates must remain simple and presentation-focused.
- Avoid embedding business logic inside HTML.
- Use `base.html` as the single layout source.

All pages must extend:

`templates/base.html`

Do not duplicate layout logic.

---

# State Consistency Rule (Very Important)

Because this system supports:

- Supabase
- SQLite local cache
- HYBRID mode
- offline-first sync

Any change affecting data flow must preserve:

- synchronization logic
- `dirty` flags
- conflict resolution
- last-write-wins behavior
- Vercel serverless constraints

Never break sync integrity.

---

# Subagent Strategy

Use subagents for:

- codebase exploration
- log analysis
- debugging
- dependency mapping
- parallel research

Rules:

- One objective per subagent.
- Keep main thread minimal.
- Parallelize complex analysis.
- Increase compute when needed.

---

# Autonomous Bug Fixing

When given a bug:

1. Reproduce it.
2. Analyze logs and traces.
3. Identify root cause.
4. Implement fix.
5. Verify fix.
6. Add regression test if appropriate.

No temporary patches.

Always fix the underlying cause.

---

# Mandatory Verification

No task is complete without proof.

Verification methods:

- Running tests
- Checking logs
- Validating edge cases
- Confirming behavior before/after change
- Ensuring CI passes

Before marking complete, ask:

“Would a staff-level engineer approve this?”

If uncertain → improve.

---

# Elegance Check

For non-trivial changes ask:

Is there a simpler, cleaner solution?

If solution feels fragile or overengineered:

Refactor toward clarity and minimalism.

Avoid unnecessary abstraction.

---

# Task Management

All active work must be tracked in:

`/ai/TODO.md`

Use checkboxes.

Update continuously during implementation.

At completion, include a short review section summarizing:

- Root cause (if applicable)
- Fix applied
- Verification result

---

# Self-Improvement Loop

When corrected:

Document in `/ai/LESSONS.md`:

Mistake  
Cause  
Rule preventing recurrence  

Review this file at the beginning of each session.

---

# Engineering Principles

## Simplicity First
Prefer the smallest correct solution.

## Root Cause Thinking
Never apply temporary fixes when systemic causes exist.

## System Integrity
All changes must preserve:
- data consistency
- offline-first behavior
- sync reliability
- mobile compatibility
- PWA functionality
