# 07: Document the final CLI workflow in STE100 style

**What to build:** Developers can build, install, and use the finished rails-map CLI by following short, clear README instructions. The instructions match the released behavior and state measured performance without overstating it.

**Blocked by:** 01: Certify the Rails navigation contract; 02: Close audited navigation gaps; 03: Prove Antigravity CLI can retrieve navigation data; 04: Reach fivefold speed for full maps; 05: Reach fivefold speed for action inspection; 06: Ratchet and prove the release gate

**Status:** done

- [x] Review README commands against the verified build and installation process.
- [x] Document `map` and `inspect` usage with useful examples and clear output guidance.
- [x] Use short sentences and common words in STE100 style.
- [x] Explain static-analysis limits and show only performance claims supported by issue 06 evidence.
- [x] Verify every documented command against the final CLI.

## Comments

- 2026-10-16: Updated README build, install, use, output, and verification instructions. Documented static-analysis limits and only the six ratios measured by issue 06. Built the native CLI, copied it to a temporary PATH-like install location, and ran all three documented map/inspect examples successfully against `fixtures/rails61`.
