# 03: Prove Antigravity CLI can retrieve navigation data

**What to build:** An `agy` task can retrieve an expected route and view through rails-map while CodeLens is unavailable, then cite the CLI's source paths and lines.

**Blocked by:** 02: Close audited navigation gaps

**Status:** done

- [x] Run a bounded `agy` task against a pinned Rails repository with CodeLens unavailable.
- [x] Require the task to find expected route and view evidence by running rails-map.
- [x] Verify cited paths and lines against the repository.
- [x] Record model-trial evidence separately from CLI and harness tests.

## Comments

- 2026-10-16: User-directed substitution used Antigravity CLI 1.4.0 with Claude Sonnet 4.6. The bounded read-only task ran `bin/rails-map inspect TopicsController#show --root bench/corpus/discourse --json` on Discourse commit `802125b979b5bb848a7cfc52409ef3176ffd4d82`. The agent returned nine direct `GET` routes for `topics#show` and conventional view `app/views/topics/show.html.erb`. Verified route evidence in `config/routes.rb` at lines 1531, 1631, 1640, 1647, 1667, 1672, 1682, 1683, and 1688; verified view relationship at `app/controllers/topics_controller.rb:73`. This is an `agy` model-trial result, separate from CLI parity and harness gates.
