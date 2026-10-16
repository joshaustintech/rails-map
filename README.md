# rails-map

## Introduction

Rails applications can spread navigation details across routes, controllers,
views, and models. A code search can find text, but it does not show how these
parts connect. Rails console and runtime tools can show runtime behavior, but
they need a working application and may run application code.

rails-map reads source files without starting Rails or running application
code. It links supported routes, actions, views, and models. It also reports
source evidence and patterns it cannot resolve. Use it to inspect a project
when you need a source-based map without running the application. It cannot
prove behavior created at run time.

rails-map reads Rails source files. It does not start Rails or run app code.
Use it to find routes, actions, views, models, and model links. It also lists
source patterns it cannot resolve.

## Requirements

- macOS on Apple silicon
- Spinel compiler to build the CLI
- Ruby, Prism, Flay, and Reek to run the development checks

The CLI is a native executable. It does not need Ruby, Prism, or Rails at run
time.

## Build and install

Put `spinel` on your `PATH`, then build the CLI:

```sh
bin/build
```

The build writes `build/rails-map`. Copy it to a directory on your `PATH`:

```sh
mkdir -p "$HOME/.local/bin"
cp build/rails-map "$HOME/.local/bin/rails-map"
```

Add `$HOME/.local/bin` to your `PATH` if needed.

## Use

Run the command from a Rails project. The current directory is the default
project root. Use `--root` to select another project.

```sh
rails-map map --json
rails-map inspect UsersController#show --json
rails-map map --root fixtures/rails61 --json
```

`map` lists all supported navigation facts. `inspect` limits the result to
one controller action. JSON has a `schema_version` field. Paths are relative
to the project root. Each route, view, model, or association fact includes
source evidence. Confidence is `direct`, `conventional`, or `unresolved`.
The `unresolved` list shows dynamic or unsupported patterns. Static analysis
cannot prove behavior created at Rails run time.

## Verify

`bin/verify` runs only on macOS. It requires a clean checkout and the pinned
corpus. Fetch the corpus, then run the gate:

```sh
bin/fetch-corpus
bin/verify
```

The gate builds a native CLI. It runs the behavior, mutation, Flay, and Reek
checks. It then compares canonical JSON and times `map` and `inspect` on all
three pinned repositories. Each command gets one warm-up and 30 timed runs.
JSON parsing and compilation are outside the timed interval. Every timed
result must match the CRuby and Prism reference. Each Spinel median must be
at most 0.20 of the reference median. Tool versions and repository commits
must match `bench/baseline.json` and `bench/repositories.lock`.

The 2026-10-16 run used CRuby 3.4.9, Prism 1.9.0, and Spinel
`a753180b` on macOS arm64. The map/inspect ratios were 0.0861/0.0849 for the
sample app, 0.1949/0.1856 for CASA, and 0.1750/0.1759 for Discourse. These
results apply to the pinned checkouts. They do not show performance on every
Rails project.
