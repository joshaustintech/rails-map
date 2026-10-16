# 04: Reach fivefold speed for full maps

**What to build:** `rails-map map` returns the same canonical navigation data as CRuby + Prism and has a median runtime at least five times faster on each pinned Rails repository.

**Blocked by:** 02: Close audited navigation gaps

**Status:** done

- [x] Profile all three repositories and identify the measured bottlenecks.
- [x] Optimize full-map analysis without dropping semantic evidence or changing canonical output.
- [x] Run one warm-up and 30 timed runs for each implementation on the same checkout and Mac.
- [x] Record versions, commits, output equality, medians, and speed ratios; require ratio at most 0.20 in all map cases.

## Comments

- 2026-10-16: Time Profiler and phase timing identified repeated route/view membership scans, repeated view-file discovery, template model parsing unused by full-map output, and model-association line processing. Replaced linear membership checks with hash indexes, used exact supported-extension file checks for literal views, and limited template-model parsing to targeted inspection. Canonical JSON matched on each pinned repository.
- Benchmark: `SPINEL=/Users/josh/reef/target/spinel/bin/spinel ruby bench/run.rb --maps-only --map-max-ratio 0.20`; CRuby 3.4.9, Prism 1.9.0, Spinel `a753180b` (Apple Clang 21.0.0); one warm-up plus 30 timed process runs; parsing/build time excluded. Corpus commits: sample app `f118bc34a66be4e420d448290e437e63f8b96db2`, CASA `b584d2e6e6ebffe382f34c2ec202d20384d035ca`, Discourse `802125b979b5bb848a7cfc52409ef3176ffd4d82`. Medians: sample 81.072 ms vs 7.138 ms (0.0881); CASA 153.281 ms vs 29.000 ms (0.1892); Discourse 1041.325 ms vs 180.307 ms (0.1732). The runner checked canonical JSON equality during warm-up and every timed run.
- Full `bin/verify`: 21 tests, 128 assertions; 12/12 mutants killed; zero Reek warnings; Flay score 0; all six map/inspect ratios <= 0.20.
