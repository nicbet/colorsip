# Flesh out product spec and derive backlog

## What
Rewrite `spec.md` into a complete product spec for Colorsip. It includes every decision from the 2026-10-14 Q&A (issue description and comments), the agent-picked defaults, and a release tag (MVP / V2 / V3) on each feature. The spec ends with a proposed backlog, which gets filed as feature issues under cs-54d4cf once the user approves it.

## Why
The original spec was a feature wish list with gaps (permissions, storage model, paste mechanics, scope). We need one source of truth to derive and order the backlog from.

## How
- Keep spec.md as the product document. Sections: overview and principles, platform, roadmap, then one section per feature area with release tags, the data model, the file format, permissions/onboarding, settings, and non-goals.
- Mockups (gitignored `design/`) are described in words, so the spec stands on its own.
- A "Proposed backlog" section groups work items by release, with dependencies.

## Acceptance criteria
- [ ] Every Q&A answer is reflected in spec.md
- [ ] Agent-picked defaults are marked as tunable
- [ ] Each feature carries a release tag
- [ ] Proposed backlog reviewed by the user, then filed under cs-54d4cf with dependency links
