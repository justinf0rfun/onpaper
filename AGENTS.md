# AGENTS.md

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues for `justinf0rfun/onpaper`; external PRs are not a triage request surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default Matt Pocock engineering-skill label vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repo: read `CONTEXT.md` and relevant ADRs under `docs/adr/` before implementation or design work. See `docs/agents/domain.md`.

## macOS UI and OpenNook

OpenNook is the host shell for the onpaper tray. For UI, chrome, surface, notch behavior, theming, settings, compact/expanded transitions, menu-bar presence, and interaction affordances, prefer OpenNook's public configuration seams first:

- Use `NookConfiguration`, `NookPreferenceDefaults`, `NookAppearancePreferences`, `NookStyle`, `NookChromeMetrics`, `NookChromeTypography`, `NookChromeMotion`, `NookChromeBehavior`, `NookHostBranding`, and OpenNook environment values before writing custom chrome.
- Read `@Environment(\.nookResolvedTheme)` for colors/tints inside onpaper views instead of hardcoding light/dark palettes.
- Let OpenNook Settings own user-facing appearance choices such as dark/light, solid/translucent/Liquid Glass, accent, presentation, and glass strength. Host defaults may seed first-run behavior, but must not silently override persisted user settings unless there is a documented product reason.
- Use OpenNook compact slots, top-bar configuration, status/banner, settings, and presentation APIs before building replacement interactions.
- Write custom SwiftUI only for onpaper's product-specific content and workflows, such as captured assets, packet controls, packet preview, and delivery state.
- If OpenNook cannot express a required UI or interaction, document the gap in the implementation notes or issue before adding local custom behavior.
