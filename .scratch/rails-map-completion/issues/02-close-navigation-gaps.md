# 02: Close audited navigation gaps

**What to build:** Developers can navigate supported Rails routes, controller actions, views, models, and associations across the independently audited syntax cases. Dynamic behavior remains clearly unresolved.

**Blocked by:** 01: Certify the Rails navigation contract

**Status:** complete

- [x] Fix each supported behavior gap recorded by issue 01.
- [x] Scope render uncertainty to the selected action and distinguish a literal layout from a dynamic template target.
- [x] Add end-to-end CLI cases for explicit and conventional routes and views, namespaced actions, associations, and dynamic patterns.
- [x] Preserve source path, line, confidence, deterministic JSON, and reference parity.
- [x] Record unsupported Rails behavior as unresolved instead of guessing.

**Verification:** `bin/verify` passed on all three pinned repositories: 21 tests, 128 assertions; 12/12 mutants killed; Flay 0; Reek 0; canonical reference parity passed; all six benchmark ratios were 0.0977–0.4498.

## Comments

- ADR 0009 documents action-scoped render uncertainty, the literal-layout rule, and preservation of the schema version 1 JSON shape.
- Independent standards and spec reviews found no remaining issues.
