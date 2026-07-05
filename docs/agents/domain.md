# Domain Docs

How engineering skills should consume this repo's domain documentation.

## Layout

This is a single-context repo.

Read before implementation, issue triage, debugging, refactoring, or architecture work:

- `CONTEXT.md`
- relevant ADRs under `docs/adr/`
- `docs/onpaper-prd.md`
- `docs/onpaper-technical-design.md`

If an ADR does not exist for the area being changed, proceed with the PRD and technical design as the authoritative context.

## Use Canonical Terms

Use product terms from `CONTEXT.md` in issue titles, test names, implementation notes, and review findings. Prefer `ContextAsset`, `ContextPacket`, `DeliveryAttempt`, and `AIDestination` over vague alternatives.

## Flag Conflicts

If a proposed change conflicts with the PRD, technical design, or an ADR, surface that explicitly before implementing.

