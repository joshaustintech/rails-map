# rails-map Agent Guide

Use Spinel Ruby for the CLI. Preserve the JSON contract shared with the CRuby + Prism reference. Record architecture decisions in `docs/adr/`.

Read [AI-HARNESS.md](docs/AI-HARNESS.md) before implementation work. Run `bin/verify` before completion. It is the acceptance gate for the compiler, behavior, mutations, Flay, Reek, and benchmarks.

Write no C. Use Rust only after a Spinel feasibility probe proves a required parser cannot run in Spinel. Rust must use the standard library and contain no `unsafe`, `unwrap`, or `panic`.

## Agent skills

### Issue tracker

Track specs and issues as Markdown under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Keep actionable issues agent-ready. Resolve safe uncertainty autonomously and record architectural choices as ADRs. See `docs/agents/triage-labels.md`.

### Domain docs

Use the single-context layout and read relevant ADRs. See `docs/agents/domain.md`.
