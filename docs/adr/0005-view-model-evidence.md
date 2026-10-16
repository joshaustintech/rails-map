# ADR 0005: Read model references from view code

## Status

Accepted

## Context

An action can reference a model from its controller or a related view. ERB templates mix HTML and Ruby code. Scanning the full template text treats comments and labels as source code.

## Decision

Read model constants only from Ruby code inside ERB tags. Ignore ERB comments. Use Prism in the development reference and a small lexical scan in the compiled Spinel CLI. Limit inspect results to evidence paths connected to the selected action, its views, its models, and the route file.

## Consequences

The CRuby reference stays independent from the compiled CLI. A view-only model can add model and association rows to inspect output. Dynamic behavior in unrelated files does not appear in an inspect result.
