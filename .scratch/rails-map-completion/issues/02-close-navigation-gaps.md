# 02: Close audited navigation gaps

**What to build:** Developers can navigate supported Rails routes, controller actions, views, models, and associations across the independently audited syntax cases. Dynamic behavior remains clearly unresolved.

**Blocked by:** 01: Certify the Rails navigation contract

**Status:** ready-for-agent

- [ ] Fix each supported behavior gap recorded by issue 01.
- [ ] Scope render uncertainty to the selected action and distinguish a literal layout from a dynamic template target.
- [ ] Add end-to-end CLI cases for explicit and conventional routes and views, namespaced actions, associations, and dynamic patterns.
- [ ] Preserve source path, line, confidence, deterministic JSON, and reference parity.
- [ ] Record unsupported Rails behavior as unresolved instead of guessing.
