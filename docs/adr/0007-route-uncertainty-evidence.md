# ADR 0007: Report uncertainty at dynamic route evidence

## Status

Accepted

## Context

The Prism reference treated a dynamic scope path as an empty path and emitted child routes that source code could not prove. It also missed dynamic local values that later shaped routes, and some uncertainty rows pointed to the start of a chained expression instead of the route call or option value.

## Decision

Reject a scope whose path or module expression is dynamic. Emit a `dynamic_route` row at the scope line and do not emit routes beneath it. Treat a dynamic local assignment that is read in the route file as unresolved at its expression line. Use the call message line for chained route generators. Point unsupported option rows at the option value line.

## Consequences

The reference can return fewer speculative routes and more precise unresolved rows. The compiled scanner and golden cases must use the same rules before canonical parity passes.
