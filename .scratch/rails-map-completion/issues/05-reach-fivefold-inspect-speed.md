# 05: Reach fivefold speed for action inspection

**What to build:** `rails-map inspect Controller#action` returns the same canonical action-specific navigation data as CRuby + Prism and has a median runtime at least five times faster on each pinned Rails repository.

**Blocked by:** 02: Close audited navigation gaps; 04: Reach fivefold speed for full maps

**Status:** done

- [x] Profile all three repositories and identify action-inspection bottlenecks.
- [x] Reuse effective map optimizations where they preserve exact action-specific semantics.
- [x] Run one warm-up and 30 timed runs for each implementation on the same checkout and Mac.
- [x] Record versions, commits, output equality, medians, and speed ratios; require ratio at most 0.20 in all inspect cases.

## Comments

- 2026-10-16: Time Profiler traces covered all three pinned inspect commands. Samples showed whole-project scanning dominates, with route-line parsing and filesystem traversal most visible on CASA and Discourse; the sample app trace was too short to rank internal work reliably. Ticket 04's shared scan and lookup optimizations preserved exact action-specific JSON and brought every inspect case under the target.
- Benchmark: `SPINEL=/Users/josh/reef/target/spinel/bin/spinel ruby bench/run.rb --inspections-only --inspect-max-ratio 0.20`; CRuby 3.4.9, Prism 1.9.0, Spinel `a753180b` (Apple Clang 21.0.0); one warm-up plus 30 timed process runs; parsing/build time excluded. Corpus commits: sample app `f118bc34a66be4e420d448290e437e63f8b96db2`, CASA `b584d2e6e6ebffe382f34c2ec202d20384d035ca`, Discourse `802125b979b5bb848a7cfc52409ef3176ffd4d82`. Medians: sample 76.468 ms vs 6.297 ms (0.0824); CASA 141.949 ms vs 25.584 ms (0.1802); Discourse 975.001 ms vs 173.582 ms (0.1780). The runner checked canonical JSON equality during warm-up and every timed run.
- Full `bin/verify` also passed: 21 tests, 128 assertions; 12/12 mutants killed; zero Reek warnings; Flay score 0.
