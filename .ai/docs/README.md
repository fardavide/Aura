# Aura — project docs

Narrative knowledge for humans and agents: how the app is built, **why**, and where it's at.
Distinct from `.claude/skills/` (actionable, trigger-activated *rules*) — these docs are the
*explanation* and *state*. Tool-agnostic, so any agent (Claude, Gemini, …) can read them.

| Doc | Holds |
|-----|-------|
| [architecture.md](architecture.md) | How the code is organised — feature-vertical Clean Architecture, the `AuraKit` package, the dependency rule, DI |
| [decisions.md](decisions.md) | Why — the key decisions and their rationale (ADR-style) |
| [frigate-integration.md](frigate-integration.md) | What we learned about Frigate — connection model, verified go2rtc stream path, auth reality |
| [status.md](status.md) | Where we are — slice progress, roadmap, and runtime config still needed |

## For agents

- **Read `architecture.md` + `decisions.md` before any non-trivial change** so you don't
  break a layer boundary or re-litigate a settled decision.
- For *how-to* conventions (writing Swift/tests, the Frigate API contracts), use the
  `.claude/skills/` — `/architecture`, `/swift-style`, `/swift-testing`, `/frigate-rest`, `/frigate-live`.
- **Keep these current**: record a new architectural decision in `decisions.md`, update
  `status.md` when a slice lands, and add Frigate findings to `frigate-integration.md`.
- Describe concepts and contracts, not specific type/function names — they rot on rename.
