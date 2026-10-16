# ADR 0001: Analyze Rails source without booting the application

## Status

Accepted

## Context

Rails routes and rendered views are not always available through editor LSP methods. Booting a project can execute application code, require project dependencies, and still fail to expose every source relationship.

## Decision

Read Rails source files statically. Report direct source evidence separately from conventions inferred from file layout. Mark detected dynamic or unsupported route and render behavior unresolved.

## Consequences

The tool works without installing or booting the target Rails app. Runtime-generated routes and views remain incomplete by design and must be visible in output.
