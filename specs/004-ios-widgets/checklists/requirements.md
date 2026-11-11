# Specification Quality Checklist: iOS Widgets

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-11-09
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Platform terms (Home Screen, Lock Screen, Dynamic Type, VoiceOver) are the user-facing names of
  the surfaces requested, not implementation choices.
- Re-validated 2026-11-09 after the self-refresh, recognition (FR-023) and sky-artwork (FR-024)
  changes: no [NEEDS CLARIFICATION] markers; FR and SC numbering put back in order; the draft
  direction's "soft glow" wording corrected to the app's curtains. All items pass.
- Open choices were resolved with defaults recorded in Assumptions: widgets follow the app's
  place (no per-widget configuration), large/extra-large/StandBy are out of scope.
- Phase 7 review 2026-11-11 (T050), simulator (iPhone 17 Pro, iOS 27):
  - Medium widget at the largest accessibility text size in fi, sv and en: level word, reason,
    place and age fit, no clipping or overlap (SC-005). The widget had fetched for itself
    ("1 min ago"), and the stale look showed earlier that day (SC-004).
  - Not checked here: small and the three Lock Screen layouts at the largest size, tinted and
    always-on rendering, and SC-001/003/006/008, which need people or the phone. They stay with
    the device run of quickstart.md (T052).
  - Privacy (T048): the extension contacts only opendata.fmi.fi and services.swpc.noaa.gov, has
    no location Info.plist keys and no CoreLocation symbols; both privacy manifests now give
    reason 1C8F.1 for the App Group UserDefaults. Archive privacy report not yet checked.
