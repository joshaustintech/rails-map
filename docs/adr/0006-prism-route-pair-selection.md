# ADR 0006: Select route pairs from option hashes

## Status

Accepted

## Context

The CRuby + Prism reference accepted a route hash only when it had one pair.
Rails permits a route pair and option pairs in the same call, such as a path,
controller target, and `constraints` option. The old reader omitted those routes.

## Decision

Select the static path-to-controller pair from all pairs in the route hash.
Keep option handling separate. The Spinel scanner and reference must emit the
same route and uncertainty rows.

## Consequences

The reference contract changes for routes that were previously omitted. Update
the pinned corpus baseline and compare both implementations before release.
