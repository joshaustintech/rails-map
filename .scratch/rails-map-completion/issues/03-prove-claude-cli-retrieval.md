# 03: Prove Claude Code can retrieve navigation data

**What to build:** A Claude Code task can retrieve an expected route and view through rails-map while CodeLens is unavailable, then cite the CLI's source paths and lines.

**Blocked by:** 02: Close audited navigation gaps

**Status:** ready-for-agent

- [ ] Run a bounded Claude Code task against a pinned Rails repository with CodeLens unavailable.
- [ ] Require the task to find expected route and view evidence by running rails-map.
- [ ] Verify cited paths and lines against the repository.
- [ ] Record model-trial evidence separately from CLI and harness tests.
