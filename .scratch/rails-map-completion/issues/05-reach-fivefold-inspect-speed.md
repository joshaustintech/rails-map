# 05: Reach fivefold speed for action inspection

**What to build:** `rails-map inspect Controller#action` returns the same canonical action-specific navigation data as CRuby + Prism and has a median runtime at least five times faster on each pinned Rails repository.

**Blocked by:** 02: Close audited navigation gaps; 04: Reach fivefold speed for full maps

**Status:** ready-for-agent

- [ ] Profile all three repositories and identify action-inspection bottlenecks.
- [ ] Reuse effective map optimizations where they preserve exact action-specific semantics.
- [ ] Run one warm-up and 30 timed runs for each implementation on the same checkout and Mac.
- [ ] Record versions, commits, output equality, medians, and speed ratios; require ratio at most 0.20 in all inspect cases.
