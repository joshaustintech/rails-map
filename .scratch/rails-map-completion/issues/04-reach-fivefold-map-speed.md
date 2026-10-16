# 04: Reach fivefold speed for full maps

**What to build:** `rails-map map` returns the same canonical navigation data as CRuby + Prism and has a median runtime at least five times faster on each pinned Rails repository.

**Blocked by:** 02: Close audited navigation gaps

**Status:** ready-for-agent

- [ ] Profile all three repositories and identify the measured bottlenecks.
- [ ] Optimize full-map analysis without dropping semantic evidence or changing canonical output.
- [ ] Run one warm-up and 30 timed runs for each implementation on the same checkout and Mac.
- [ ] Record versions, commits, output equality, medians, and speed ratios; require ratio at most 0.20 in all map cases.
