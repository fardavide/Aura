---
name: versioning
description: Aura's version-bump + changelog convention — patch by default, minor only at user-called milestones, bump the build number, and keep the README changelog in lockstep.
when_to_use: >
  Consult before bumping the app version or preparing a release/PR — editing MARKETING_VERSION or
  CURRENT_PROJECT_VERSION, or when the user says "bump the version", "cut a release", or asks for a
  minor/patch bump. Also whenever a change lands that warrants a changelog entry.
---

## Version bumps

- **Patch by default.** Bump the patch (`0.x.Y`). **Never propose or auto-apply a minor bump** —
  the user calls **minor** bumps themselves at feature milestones (e.g. 0.2.0 = camera-ordering +
  Settings menu; 0.3.0 = Cameras grid v2). Do a minor only when the user asks or confirms.
- **Bump the build number too.** `CURRENT_PROJECT_VERSION` is monotonic — increment it with every
  marketing bump so App Store Connect accepts the upload. Both keys live in
  `Aura.xcodeproj/project.pbxproj` across all build configs; keep every config consistent.

## Changelog — keep it in lockstep

- **Every version bump adds a matching entry to the `## Changelog` in `README.md`.** It is
  hand-maintained (not generated) and the user expects it current with the version — a bump with a
  stale changelog is a defect.
- Entries are **user-facing, concise, newest-first**: what changed for someone using the app, not
  the implementation. Match the existing heading format (`### <version> — <YYYY-MM-DD>`).

## Landing

- `main` is PR-gated — land every bump via a pull request and wait for the checks (see the
  `commit-directly-to-main` note). The PR that carries the change also carries its version bump and
  changelog entry.
