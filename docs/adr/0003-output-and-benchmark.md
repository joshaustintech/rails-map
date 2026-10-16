# ADR 0003: Version deterministic output and compare identical analysis

## Status

Superseded by [ADR 0010](0010-final-release-gate.md).

## Context

Agents need machine-readable navigation facts. Performance comparisons are meaningful only when both implementations analyze the same repository and return the same facts.

## Decision

Version JSON output. Sort collections and use paths relative to the scanned root. Build a development-only CRuby + Prism reference first. Require canonical JSON equality between the reference and compiled CLI. Canonical comparison sorts object keys and array items because each result collection represents independent evidence rows. Benchmark pinned repository commits with one process warm-up and 30 timed process runs per command. Parse and canonicalize JSON after each timed process returns. Require a median runtime at least 10% lower for the compiled CLI on every repository and command. Exclude compilation time.

Capture the CRuby + Prism baseline with `ruby bench/run.rb --record-baseline`. The record includes runtime versions and repository commit SHAs.

## Consequences

Any output-contract change requires a version decision. Performance results include tool and repository versions. The CRuby reference remains development-only.
