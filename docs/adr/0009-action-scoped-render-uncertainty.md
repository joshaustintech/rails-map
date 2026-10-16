# ADR 0009: Scope render uncertainty to its action

## Status

Accepted

## Context

`inspect Controller#action` selected unresolved render rows by source path. A controller file can contain several actions, so inspecting one action leaked render uncertainty from its neighbors. The scanner also treated `render layout: "bare"` as a dynamic view render, even though that literal names a layout and does not choose a template.

## Decision

Associate dynamic render uncertainty internally with its controller and action, and include it in `inspect` only when that action is selected. Remove these internal selection tags before emitting schema version 1 JSON. A render call whose options only set layout or response metadata is not a dynamic view render. Keep unresolved evidence for dynamic template targets and retain direct evidence for recognized explicit templates. Sort navigation rows by their visible keys, confidence, and source evidence so equal-key rows remain deterministic across both analyzers.

## Consequences

Action-scoped output no longer reports neighboring actions' dynamic renders. Project maps still report all dynamic renders. Literal layout options do not create false uncertainty. Equal-key rows have an explicit source-based order. The CRuby + Prism reference, Spinel CLI, golden cases, and pinned corpus parity must agree on these rules.
