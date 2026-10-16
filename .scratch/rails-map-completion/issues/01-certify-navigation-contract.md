# 01: Certify the Rails navigation contract

**What to build:** Independently reviewed examples define which route, controller action, view, model, association, and uncertainty facts rails-map must return. Developers and agents can tell supported evidence from inference.

**Blocked by:** None (can start immediately)

**Status:** complete

- [x] Add hand-reviewed expected facts for supported Rails 6.1+ syntax and dynamic behavior.
- [x] Check `map` and `inspect` output against those facts, including file paths, lines, confidence, and unresolved behavior.
- [x] Document gaps found when comparing expected facts with the current three-repository corpus.
- [x] Keep canonical JSON deterministic and compatible with the CRuby + Prism reference.

**Verification:** `bin/verify` passed: 19 tests, 112 assertions; 12/12 mutation kills; Flay/Reek clean; six benchmark cases recorded.

## Comments

- See [navigation contract audit](../../../docs/evidence/navigation-contract-audit.md) for independently checked fixture facts, pinned-corpus examples, and the render uncertainty gap deferred to issue 02.
