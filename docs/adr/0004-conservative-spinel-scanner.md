# ADR 0004: Keep the compiled scanner conservative

## Status

Accepted

## Context

The Spinel runtime does not expose Prism or Ripper as Ruby libraries. A compiled executable cannot load the development reference parser.

## Decision

Use a small Spinel Ruby source scanner for the compiled CLI. Emit evidence for patterns it can resolve and `unresolved` rows for dynamic route, render, and association forms. Do not embed C. Keep the CRuby + Prism analyzer as the semantic oracle and narrow scanner gaps before claiming parity.

## Consequences

The compiled tool has a lower runtime and no Rails runtime dependency, but its supported syntax is narrower than the reference. The benchmark gate must compare canonical JSON and cannot pass until both analyzers produce equal results on each pinned repository.
