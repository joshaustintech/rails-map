# ADR 0002: Keep the CLI in compiled Spinel Ruby

## Status

Accepted

## Context

The tool must be a native CLI and the user requires Spinel Ruby. Hand-authored or embedded C is prohibited. Native code is allowed only when Spinel Ruby cannot provide a required capability.

## Decision

Implement the CLI and analysis in Spinel Ruby. Use a Rust helper only after a reproducible feasibility probe shows a necessary parser cannot run in Spinel. Such a helper uses only the Rust standard library and contains no `unsafe`, `unwrap`, or `panic`.

## Consequences

The delivered CLI has a small implementation surface. Any Rust fallback adds a separate build artifact and must preserve the Ruby-defined output contract.
