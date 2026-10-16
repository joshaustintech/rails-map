# rails-map completion and fivefold performance spec

**Status:** In progress
**Date:** 2026-10-16

## Problem Statement

Claude Code's LSP client does not request `textDocument/codeLens`. The
`ruby-lsp-rails` issue asks for controller-action route and view information
through another LSP method. The issue remains open as of 2026-10-16. See
[ruby-lsp-rails issue 694](https://github.com/Shopify/ruby-lsp-rails/issues/694).

rails-map provides a separate static CLI. It maps routes, controller actions,
view candidates, models, and associations. It does not change
`ruby-lsp-rails` or add a non-CodeLens LSP method. A user-directed Antigravity
CLI (`agy`) trial proved that an agent can retrieve and cite navigation facts.

The initial CLI passed a 10% performance gate. That was not proof of complete
Rails coverage. The reference and compiled scanner can share mistaken
assumptions, and the corpus contains only three sparse source checkouts.

The request then moved beyond its original threshold. The measured
Spinel-to-CRuby + Prism runtime ratios were 0.1287 and 0.1014 for the sample
app, 0.4831 and 0.2966 for CASA, and 0.3032 and 0.2905 for Discourse, for
`map` and `inspect` respectively. Only two of six comparisons reached 5x.
The slowest case was CASA `map` at about 2.1x. The gate then permitted ratios
as high as 0.90.

## Solution

Finish rails-map as an agent-usable static navigation tool. Define and test
its Rails syntax support against independently reviewed expected facts. Keep
unknown runtime behavior visible as unresolved evidence. Run an agent CLI
trial that retrieves route and view facts and cites their source locations.

Profile the six pinned benchmark cases, optimize their actual bottlenecks, and
raise the per-case target to at least 5x the contemporaneous CRuby + Prism
median. Keep semantic equality, source evidence, mutation, Flay, and Reek gates.

This solves the practical access problem through an agent-usable CLI. It does
not close the upstream LSP request. Do not claim that request is fixed unless
a separate `ruby-lsp-rails` change exposes the information through a supported
non-CodeLens method.

## User Stories

1. As a developer, I want to map a Rails project without booting it, so that
   I can inspect navigation metadata without running application code.
2. As a developer, I want to inspect one controller action, so that I can see
   only its relevant routes, views, models, associations, and uncertainty.
3. As a code agent, I want to retrieve controller-action navigation data
   without CodeLens, so that I can use the data in a coding task.
4. As a coding-agent user, I want the project instructions to show how to run
   rails-map, so that I do not need to know an undocumented command.
5. As a developer, I want route and view rows to include relative source paths
   and line numbers, so that I can verify each result in the repository.
6. As a developer, I want direct and conventional relationships to show
   different confidence values, so that I can separate source facts from
   naming-based inference.
7. As a developer, I want dynamic or unsupported behavior reported as
   unresolved, so that the CLI does not present guesses as facts.
8. As a developer, I want common explicit and conventional routes represented,
   so that I can navigate without reading route files first.
9. As a developer, I want namespaced and nested controllers represented, so
   that route and action names remain useful in larger Rails applications.
10. As a developer, I want direct and conventional view candidates represented,
    so that I can find the template used by an action.
11. As a developer, I want models referenced by the action and its views,
    so that navigation includes data objects used by the feature.
12. As a developer, I want associations for those models, so that I can follow
    common model relationships from an action.
13. As an agent author, I want deterministic, versioned JSON, so that tools can
    consume results without editor-specific parsing.
14. As a developer, I want invalid roots, missing actions, and malformed
    commands to fail clearly, so that automation can handle errors.
15. As a macOS user, I want a documented way to install and run the compiled
    CLI, so that the target Rails project needs no Spinel compiler at runtime.
16. As a performance-conscious developer, I want every repository and command
    case to run at least 5x faster than CRuby + Prism, so that large projects
    remain practical for repeated agent calls.
17. As a maintainer, I want benchmark results tied to tool versions and full
    repository commits, so that performance claims can be repeated.
18. As a maintainer, I want benchmark runs to compare identical semantic
    output, so that speed gains do not come from skipped analysis.
19. As a maintainer, I want non-equivalent mutations killed in parallel, so
    that core navigation behavior has strong regression protection.
20. As a maintainer, I want zero Flay and Reek findings, so that the source
    stays readable and easy to change.
21. As a user, I want the output schema to remain explicit, so that changes to
    the CLI do not silently break agent consumers.
22. As a user, I want the tool to state its static-analysis limits, so that I
    know when a Rails runtime or editor integration is still needed.

## Implementation Decisions

- Keep the compiled CLI in Spinel Ruby. Do not write or embed C. Use Rust only
  if a required parser is proven infeasible in Spinel; any such Rust must use
  the standard library and contain no `unsafe`, `unwrap`, or `panic`.
- Keep CRuby + Prism as a development oracle, not a runtime dependency.
- Keep `map` and `inspect Controller#action` as the user-facing commands.
- Keep JSON versioned, deterministic, and rooted in relative paths. Include
  source line and confidence for each relationship. Use unresolved evidence
  for behavior the source cannot prove.
- Test the CLI as the primary seam. Compare canonical JSON on the same pinned
  repositories, but also add independently reviewed expected facts. Oracle
  parity alone is not correctness evidence.
- Preserve the initial 10% gate while profiling and optimizing. Raise the
  final gate to a 0.20 median ratio per repository and command after every
  case meets the 5x target.
- Measure one warm-up and 30 timed process runs per command. Exclude compile
  time and record CRuby, Prism, Spinel, and full repository commit versions.
- Keep benchmark cases on the same Mac and same checkout for each paired run.
- Treat agent CLI retrieval as a separate acceptance test from static CLI
  parity. Treat an upstream non-CodeLens LSP method as a separate project.

## Testing Decisions

- Test external CLI behavior, not internal scanner methods.
- Use the current CLI process tests for command errors, invalid roots,
  namespaced actions, explicit and conventional routes and views, models,
  associations, and unresolved behavior.
- Add hand-reviewed golden facts for Rails 6.1 syntax and dynamic behavior.
  Golden facts must not be generated from the CRuby oracle under test.
- Compare canonical JSON from the compiled CLI and CRuby + Prism on all pinned
  repositories for both commands.
- Run an agent CLI task with editor navigation unavailable. Require it to
  retrieve an expected route and view from the CLI and cite their source paths
  and lines. Report this as model-trial evidence, separate from CLI tests.
- Profile and time one warm-up plus 30 runs for each of the six repository and
  command pairs. Require exact semantic equality on every timed run and a
  median speed ratio of at most 0.20 in the final gate.
- Run all non-equivalent mutants concurrently. Require every mutant to change
  output or fail the CLI. Document any proven equivalent mutant.
- Require zero Flay findings, zero Reek warnings, a successful native macOS
  build, and a clean whitespace check.
- Existing prior art: CLI integration tests, golden navigation tasks, the
  CRuby + Prism reference, pinned-corpus benchmarks, and the parallel mutation
  gate.

## Out of Scope

- Changing `ruby-lsp-rails` to add a hover, definition, or other LSP method.
- Booting Rails or evaluating project code to resolve runtime-generated
  routes, views, or associations.
- Claiming complete support for every Rails version or plugin.
- Linux and Windows native binaries.
- Replacing the CLI with an editor-specific protocol.

## Further Notes

### Honest completion assessment

- **Current CLI plan:** implemented and verified against its present contract.
- **Original issue:** partially addressed. The CLI provides an alternate
  access path, and the AGY trial proves one agent can retrieve navigation
  facts. There is no upstream LSP change.
- **Rails coverage:** unproven beyond fixtures and three sparse repositories.
- **Performance:** all six final cases passed the 0.20 ratio limit. The clean
  full verification at `d3add22` measured ratios 0.0861 and 0.0849 for the
  sample app, 0.1949 and 0.1856 for CASA, and 0.1750 and 0.1759 for Discourse
  (`map`, `inspect`).
- **Release gate:** clean macOS arm64 run passed with 21 tests, 128 assertions,
  12/12 mutants killed, Flay 0, Reek 0, and a native Mach-O arm64 build.

The benchmark runner measures CRuby + Prism and Spinel on the pinned corpus.
It checks canonical JSON on warm-up and every timed run, enforces a maximum
0.20 median ratio, and rejects toolchain or corpus drift from the baseline.
