# 06: Ratchet and prove the release gate

**What to build:** One deterministic verification command proves navigation correctness, Claude Code retrieval, exact benchmark semantics, fivefold performance, mutation strength, source quality, and a native macOS build.

**Blocked by:** 03: Prove Claude Code can retrieve navigation data; 04: Reach fivefold speed for full maps; 05: Reach fivefold speed for action inspection

**Status:** ready-for-agent

- [ ] Require exact canonical JSON equality before accepting any timed comparison.
- [ ] Enforce a maximum Spinel-to-CRuby median ratio of 0.20 in every repository and command case.
- [ ] Run non-equivalent mutation cases concurrently and kill every non-equivalent mutant; document proven equivalents.
- [ ] Require zero Flay findings, zero Reek findings, and a successful native macOS build.
- [ ] Run the complete gate from a clean checkout with pinned corpus and tool versions.
