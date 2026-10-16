# 06: Ratchet and prove the release gate

**What to build:** One deterministic verification command proves navigation correctness, recorded agent CLI retrieval, exact benchmark semantics, fivefold performance, mutation strength, source quality, and a native macOS build.

**Blocked by:** 03: Prove Antigravity CLI can retrieve navigation data; 04: Reach fivefold speed for full maps; 05: Reach fivefold speed for action inspection

**Status:** done

- [x] Require exact canonical JSON equality before accepting any timed comparison.
- [x] Enforce a maximum Spinel-to-CRuby median ratio of 0.20 in every repository and command case.
- [x] Run non-equivalent mutation cases concurrently and kill every non-equivalent mutant; document proven equivalents.
- [x] Require zero Flay findings, zero Reek findings, and a successful native macOS build.
- [x] Run the complete gate from a clean checkout with pinned corpus and tool versions.

## Comments

- 2026-10-16: `bin/verify` passed from clean `main` at `a9004946a281a37802d7f5e0d69824e87949b381` on Darwin arm64 with CRuby 3.4.9, Prism 1.9.0, and Spinel `spinel unreleased (a753180b) [apple clang 21.0.0 (cc)]`. The runner rejects toolchain or corpus drift against `bench/baseline.json`, and checks canonical JSON equality on the warm-up and every timed process. All 12 non-equivalent mutants were killed concurrently; there are no equivalent mutants to waive. Flay score 0; Reek warnings 0. Build output is a Mach-O 64-bit arm64 executable.
- Six 30-run median ratios (map, inspect): sample app 0.0910, 0.0816; CASA 0.1985, 0.1779; Discourse 0.1769, 0.1733. Each case passed the 0.20 maximum. The complete test suite passed with 21 tests and 128 assertions.
