# Phase 1 — Command palette search refinement

## Change
- Corrected the whitespace tokenization used by command matching. The previous regular expression matched the literal characters "\\s" instead of whitespace, so commands that matched only at the start of a later word could be ranked as substring/fuzzy matches or missed.
- Added focused unit tests for whole-word prefix ranking, later-word matching, fuzzy initials with stable ordering, case/trim normalization, and result limits.

## Scope and compatibility
- No UI behavior, command actions, editor controllers, project files, or engine components were changed.
- Existing command palette commands and their execution callbacks remain untouched.

## Validation
- Static inspection confirms the filter now tokenizes with the whitespace expression `RegExp(r'\s+')`.
- Regression tests are committed but have not been run. Flutter analyze and Flutter test remain pending; no passing result is claimed.
